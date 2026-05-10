/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Simulateur ECU (Moteur) - STM32F407G-DISC1
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "mcp2515.h"
#include <stdio.h>
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
SPI_HandleTypeDef hspi1;
UART_HandleTypeDef huart2;

/* USER CODE BEGIN PV */
/* ── Valeurs dynamiques simulées ── */
static uint16_t sim_rpm         = 800;   /* tr/min  — monte par paliers      */
static uint8_t  sim_speed       = 0;     /* km/h    — suit le RPM            */
static uint8_t  sim_coolant     = 20;    /* °C      — monte progressivement  */
static uint8_t  sim_fuel        = 100;   /* %       — descend lentement      */
static uint16_t sim_battery_mv  = 14000; /* mV      — oscille 13500..14400   */
static uint8_t  sim_battery_dir = 0;     /* 0=descend 1=monte                */
static uint8_t  sim_engine_load = 20;   /* % — suit le RPM */
static uint16_t sim_avg_consumption = 150; /* 15.0 L/100km au démarrage */

/* ── Chronomètres ── */
static uint32_t last_heartbeat  = 0;     /* Affichage périodique console     */
static uint32_t last_temp_tick  = 0;     /* Montée température (toutes 3s)   */
static uint32_t last_fuel_tick  = 0;   /* Fuel    : toutes les 10s */
static uint32_t last_batt_tick  = 0;   /* Batt    : toutes les 2s  */

/* ── Buffers CAN ── */
static can_frame rxMsg;
static can_frame txMsg;

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_SPI1_Init(void);
static void MX_USART2_UART_Init(void);

/* USER CODE BEGIN PFP */
/* --- Redirection printf vers UART2 --- */
#ifdef __GNUC__
#define PUTCHAR_PROTOTYPE int __io_putchar(int ch)
#else
#define PUTCHAR_PROTOTYPE int fputc(int ch, FILE *f)
#endif

PUTCHAR_PROTOTYPE
{
  HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1, HAL_MAX_DELAY);
  return ch;
}
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* ─── Mise à jour des valeurs dynamiques ──────────────────────── */

/**
 * @brief  Fait monter le RPM par paliers de 150 tr/min.
 *         Retour au ralenti (800) après 4000.
 *         Met à jour la vitesse proportionnellement.
 */
static void sim_update_rpm(void)
{
    sim_rpm += 150;
    if (sim_rpm > 4000) sim_rpm = 800;

    if (sim_rpm <= 800) {
        sim_speed           = 0;
        sim_engine_load     = 20;
        sim_avg_consumption = 80; /* Ralenti : 8.0 L/100km symbolique */
    } else {
        uint32_t v = ((uint32_t)(sim_rpm - 800) * 130) / (4000 - 800);
        sim_speed = (uint8_t)(v > 130 ? 130 : v);

        /* Engine Load : 20% → 85% */
        sim_engine_load = (uint8_t)(20 + ((uint32_t)(sim_rpm - 800) * 65)
                          / (4000 - 800));

        /* Fuel rate interne (L/h × 10) : 5.0 → 12.0 L/h
         * CORRECTION : plage réduite de 50..120 (×10)          */
        uint32_t fr_x10 = 50 + ((uint32_t)(sim_rpm - 800) * 70)
                               / (4000 - 800);

        /* Conso (L/100km × 10) = fr_x10 * 100 / speed
         * ×10 annule le ×10 du fr, ×100 donne le /100km        */
        uint32_t conso = (fr_x10 * 100UL) / sim_speed;
        if (conso > 120) conso = 120; /* Plafond 12.0 L/100km   */
        if (conso <  40) conso =  40; /* Plancher  4.0 L/100km  */
        sim_avg_consumption = (uint16_t)conso;
    }
}

/**
 * @brief  Fait monter la température moteur progressivement.
 *         Appelé toutes les 3 secondes. Plateau à 95°C.
 */
static void sim_update_temp(void)
{
    if (sim_coolant < 95) sim_coolant += 2;
    if (sim_coolant > 95) sim_coolant = 95;
}

/* ─── Mise à jour carburant : -1% toutes les 10s, minimum 5% ── */
static void sim_update_fuel(void)
{
    if (sim_fuel > 5) sim_fuel -= 1;
}

/* ─── Mise à jour batterie : oscille 13500..14400 mV par ±50 mV */
static void sim_update_battery(void)
{
    if (sim_battery_dir == 0) {
        if (sim_battery_mv > 13500) sim_battery_mv -= 50;
        else                        sim_battery_dir  = 1;
    } else {
        if (sim_battery_mv < 14400) sim_battery_mv += 50;
        else                        sim_battery_dir  = 0;
    }
}



/* ─── Construction et envoi d'une réponse OBD-II ─────────────── */

/**
 * @brief  Envoie la réponse OBD-II pour un PID donné.
 * @param  pid : 0x0C (RPM), 0x0D (vitesse), 0x05 (température)
 */
static void ecu_send_response(uint8_t pid)
{
    /* Initialiser la trame réponse */
    txMsg.can_id  = 0x7E8;
    txMsg.can_dlc = 8;
    txMsg.data[0] = 0x00;
    txMsg.data[1] = 0x41;  /* Réponse Mode 01 */
    txMsg.data[2] = pid;
    txMsg.data[3] = 0x00;
    txMsg.data[4] = 0x00;
    txMsg.data[5] = 0x00;
    txMsg.data[6] = 0x00;
    txMsg.data[7] = 0x00;

    switch (pid) {

        /* ── PID 0x0C : RPM ──────────────────────────────────────
         * Formule OBD-II : RPM = (A * 256 + B) / 4
         * Inverse        : raw = RPM * 4 → A = raw>>8, B = raw&0xFF
         */
        case 0x0C: {
            sim_update_rpm();  /* Incrémenter le RPM à chaque demande */
            uint32_t raw = (uint32_t)sim_rpm * 4;
            txMsg.data[0] = 0x04;
            txMsg.data[3] = (uint8_t)(raw >> 8);
            txMsg.data[4] = (uint8_t)(raw & 0xFF);
            MCP2515_SendMessage(&txMsg);
            printf("<< RPM : %d tr/min  (A=0x%02X B=0x%02X)\r\n\r\n",
                   sim_rpm, txMsg.data[3], txMsg.data[4]);
            break;
        }

        /* ── PID 0x0D : Vitesse ──────────────────────────────────
         * Formule OBD-II : Speed(km/h) = A   (valeur directe)
         * sim_speed est mis à jour par sim_update_rpm()
         */
        case 0x0D:
            txMsg.data[0] = 0x03;
            txMsg.data[3] = sim_speed;
            MCP2515_SendMessage(&txMsg);
            printf("<< Vitesse : %d km/h\r\n\r\n", sim_speed);
            break;

        /* ── PID 0x05 : Température liquide de refroidissement ───
         * Formule OBD-II : T(°C) = A - 40   →   A = T + 40
         * Plage : -40°C (A=0x00) à +215°C (A=0xFF)
         */
        case 0x05:
            txMsg.data[0] = 0x03;
            txMsg.data[3] = (uint8_t)(sim_coolant + 40);
            MCP2515_SendMessage(&txMsg);
            printf("<< Temp moteur : %d C  (A=0x%02X)\r\n\r\n",
                   sim_coolant, txMsg.data[3]);
            break;
            /* ── 0x2F : Carburant = A * 100 / 255  (%)
             *  Inverse : A = fuel% * 255 / 100
             *  Exemples : 100% → A=0xFF | 50% → A=0x7F | 5% → A=0x0D
             */
        case 0x2F:
            txMsg.data[0] = 0x03;
            txMsg.data[3] = (uint8_t)((uint16_t)sim_fuel * 255 / 100);
            MCP2515_SendMessage(&txMsg);
            printf("<< Carburant : %d%%  (A=0x%02X)\r\n\r\n",
                   sim_fuel, txMsg.data[3]);
            break;

            /* ── 0x42 : Tension batterie = (A*256 + B) / 1000  (V)
             *  sim_battery_mv en millivolts
             *  Inverse : A = mv>>8, B = mv&0xFF
             *  Exemple : 14.0V → mv=14000 → A=0x36 B=0xB0
             */
        case 0x42:
             txMsg.data[0] = 0x04;
             txMsg.data[3] = (uint8_t)(sim_battery_mv >> 8);
             txMsg.data[4] = (uint8_t)(sim_battery_mv & 0xFF);
             MCP2515_SendMessage(&txMsg);
             printf("<< Batterie : %lu.%03lu V  (A=0x%02X B=0x%02X)\r\n\r\n",
                    (unsigned long)(sim_battery_mv / 1000),
                    (unsigned long)(sim_battery_mv % 1000),
                    txMsg.data[3], txMsg.data[4]);
             break;
             /* ── PID 0x04 : Engine Load ─────────────────────────────────
              * Formule OBD-II : Load(%) = A * 100 / 255
              * Inverse        : A = load% * 255 / 100
              */
          case 0x04:
                 txMsg.data[0] = 0x03;
                 txMsg.data[3] = (uint8_t)((uint16_t)sim_engine_load * 255 / 100);
                 MCP2515_SendMessage(&txMsg);
                 printf("<< Engine Load : %d%%  (A=0x%02X)\r\n\r\n",
                        sim_engine_load, txMsg.data[3]);
                 break;

                 /* ── PID 0xF1 : Consommation moyenne (custom) ────────────────
                  * Encodage : (A*256 + B) / 10  → L/100km
                  * Exemple  : 7.4 L/100km → raw=74 → A=0x00 B=0x4A
                  */
          case 0xF1:
              txMsg.data[0] = 0x04;
              txMsg.data[3] = (uint8_t)(sim_avg_consumption >> 8);
              txMsg.data[4] = (uint8_t)(sim_avg_consumption & 0xFF);
              MCP2515_SendMessage(&txMsg);
              printf("<< Conso moy : %u.%u L/100km  (A=0x%02X B=0x%02X)\r\n\r\n",
                     sim_avg_consumption / 10,
                     sim_avg_consumption % 10,
                     txMsg.data[3], txMsg.data[4]);
              break;
        /* ── PID non supporté — pas de réponse (conforme OBD-II) */
        default:
            printf("[ECU] PID 0x%02X non supporte, pas de reponse.\r\n\r\n", pid);
            return;
    }
}

/**
 * @brief  Envoie une réponse Mode 03 contenant 2 codes défauts fictifs.
 * DTC 1: P0300 (Ratés d'allumage multiples) -> 0x03 0x00
 * DTC 2: U0123 (Perte de comm bus CAN)      -> 0xC1 0x23
 */
static void ecu_send_dtc_response(void)
{
    txMsg.can_id  = 0x7E8;
    txMsg.can_dlc = 8;
    txMsg.data[0] = 0x06; /* Longueur : Mode(1) + Nb(1) + DTC1(2) + DTC2(2) = 6 octets */
    txMsg.data[1] = 0x43; /* Réponse au Mode 03 (0x03 + 0x40) */
    txMsg.data[2] = 0x02; /* Nombre de DTCs (2) */

    /* DTC 1 : P0300 */
    txMsg.data[3] = 0x03;
    txMsg.data[4] = 0x00;

    /* DTC 2 : U0123 */
    txMsg.data[5] = 0xC1;
    txMsg.data[6] = 0x23;

    txMsg.data[7] = 0x00; /* Padding */

    MCP2515_SendMessage(&txMsg);
    printf("<< DTC Envoyes : P0300, U0123\r\n\r\n");
}

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */
  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/
  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */
  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */
  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_SPI1_Init();
  MX_USART2_UART_Init();

  /* USER CODE BEGIN 2 */
  HAL_Delay(200); // Laisse le MCP2515 s'alimenter correctement

  printf("\r\n================================================\r\n");
  printf("   SIMULATEUR ECU MOTEUR PRET\r\n");
  printf("================================================\r\n");

  /* ── Test SPI diagnostic ── */
     uint8_t canstat = MCP2515_ReadRegister(MCP_CANSTAT);
     printf("[TEST SPI] CANSTAT = 0x%02X  ", canstat);
     if (canstat == 0xFF || canstat == 0x00) {
         printf("=> ERREUR : MISO bloque. Verifiez le cablage.\r\n");
     } else {
         printf("=> OK\r\n");
     }

     /* ── Initialisation CAN ── */
     if (MCP2515_InitCAN() == 1) {
         printf("[OK] MCP2515 configure 500kbps. En ecoute...\r\n\r\n");
     } else {
         printf("[ERREUR] Echec configuration CAN.\r\n\r\n");
     }

     last_heartbeat = HAL_GetTick();
     last_temp_tick = HAL_GetTick();
     last_fuel_tick = HAL_GetTick();
     last_batt_tick = HAL_GetTick();
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
     while (1)
      {
          /* ── 1. Mise à jour température toutes les 3 secondes ── */
          if (HAL_GetTick() - last_temp_tick >= 3000) { sim_update_temp();	   last_temp_tick = HAL_GetTick(); }
          if (HAL_GetTick() - last_fuel_tick >= 10000) { sim_update_fuel();    last_fuel_tick = HAL_GetTick(); }
          if (HAL_GetTick() - last_batt_tick >= 2000)  { sim_update_battery(); last_batt_tick = HAL_GetTick(); }

          /* ── 2. Écoute du bus CAN ── */
          if (MCP2515_ReadMessage(&rxMsg) == 1) {

              /* Filtrer : requêtes OBD-II broadcast Mode 01 uniquement */
              if ((rxMsg.can_id == 0x7DF ||
                  (rxMsg.can_id >= 0x7E0 && rxMsg.can_id <= 0x7E7))){
            	  if(rxMsg.data[1] == 0x01)
                  {
                      uint8_t pid = rxMsg.data[2];
                      printf(">> REQUETE recue  ID:0x%03lX  PID:0x%02X\r\n",
                             rxMsg.can_id, pid);
                      ecu_send_response(pid);
                  }
            	  /* Traitement du Mode 03 (Lecture des codes défauts) */
            	          else if (rxMsg.data[1] == 0x03) {
            	              printf(">> REQUETE recue  ID:0x%03lX  Mode:03 (Demande DTC)\r\n", rxMsg.can_id);
            	              ecu_send_dtc_response();
            	          }

              else {
                  /* Trame reçue non OBD-II — afficher pour debug */
                  printf("[?] Trame inconnue  ID:0x%03lX  "
                         "D:[%02X %02X %02X %02X]\r\n",
                         rxMsg.can_id,
                         rxMsg.data[0], rxMsg.data[1],
                         rxMsg.data[2], rxMsg.data[3]);
              }
              }
          }

          /* ── 3. Heartbeat console toutes les 2 secondes ── */
          if (HAL_GetTick() - last_heartbeat >= 2000) {
        	  printf("[ECU] RPM=%d | Vit=%dkm/h | Temp=%dC | Fuel=%d%% | "
        	         "Batt=%lu.%03luV | Load=%d%% | Conso=%u.%uL/100km\r\n",
        	         sim_rpm, sim_speed, sim_coolant, sim_fuel,
        	         (unsigned long)(sim_battery_mv / 1000),
        	         (unsigned long)(sim_battery_mv % 1000),
        	         sim_engine_load,
        	         sim_avg_consumption / 10,
        	         sim_avg_consumption % 10);
              last_heartbeat = HAL_GetTick();
          }

      /* USER CODE END WHILE */
      /* USER CODE BEGIN 3 */
      }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE1);

  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSI;
  RCC_OscInitStruct.PLL.PLLM = 8;
  RCC_OscInitStruct.PLL.PLLN = 168;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ = 7;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV4;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV2;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_5) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief SPI1 Initialization Function
  */
static void MX_SPI1_Init(void)
{
  hspi1.Instance = SPI1;
  hspi1.Init.Mode = SPI_MODE_MASTER;
  hspi1.Init.Direction = SPI_DIRECTION_2LINES;
  hspi1.Init.DataSize = SPI_DATASIZE_8BIT;
  hspi1.Init.CLKPolarity = SPI_POLARITY_LOW;
  hspi1.Init.CLKPhase = SPI_PHASE_1EDGE;
  hspi1.Init.NSS = SPI_NSS_SOFT;
  hspi1.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_16;
  hspi1.Init.FirstBit = SPI_FIRSTBIT_MSB;
  hspi1.Init.TIMode = SPI_TIMODE_DISABLE;
  hspi1.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
  hspi1.Init.CRCPolynomial = 10;
  if (HAL_SPI_Init(&hspi1) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief USART2 Initialization Function
  */
static void MX_USART2_UART_Init(void)
{
  huart2.Instance = USART2;
  huart2.Init.BaudRate = 115200;
  huart2.Init.WordLength = UART_WORDLENGTH_8B;
  huart2.Init.StopBits = UART_STOPBITS_1;
  huart2.Init.Parity = UART_PARITY_NONE;
  huart2.Init.Mode = UART_MODE_TX_RX;
  huart2.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart2.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart2) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief GPIO Initialization Function
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOE_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();

  /*Configure GPIO pin Output Level pour PE3 et PB6 selon les CS possibles */
  HAL_GPIO_WritePin(GPIOE, GPIO_PIN_3, GPIO_PIN_SET);
  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_SET);

  /*Configure GPIO pin : CS */
  GPIO_InitStruct.Pin = GPIO_PIN_3;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOE, &GPIO_InitStruct);

  GPIO_InitStruct.Pin = GPIO_PIN_6;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);
}

void Error_Handler(void)
{
  __disable_irq();
  while (1)
  {
  }
}

#ifdef  USE_FULL_ASSERT
void assert_failed(uint8_t *file, uint32_t line)
{
}
#endif /* USE_FULL_ASSERT */
