/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : MCP2515 SPI Communication Test — TeraTerm output
  ******************************************************************************
  */
/* USER CODE END Header */

#include "main.h"
#include "mcp2515.h"
#include <string.h>
#include <stdio.h>

/* USER CODE BEGIN Includes */
/* USER CODE END Includes */

/* ─── Handles HAL ─────────────────────────────────────────────── */
SPI_HandleTypeDef  hspi1;
UART_HandleTypeDef huart2;




/* ─── Prototypes ──────────────────────────────────────────────── */
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_SPI1_Init(void);
static void MX_USART2_UART_Init(void);

/* ─── Helper UART ─────────────────────────────────────────────── */

/**
 * @brief Envoie une chaîne de caractères sur USART2 (TeraTerm).
 */
static void UART_Print(const char *str)
{
    HAL_UART_Transmit(&huart2, (uint8_t *)str, (uint16_t)strlen(str), 100);
}

/* ─── Envoi JSON structuré sur UART2 ─────────────────────────── */
/**
 * @brief  Envoie un paquet JSON compact sur USART2.
 *         Format : {"rpm":XXXX,"speed":XX,"temp":XX,"fuel":XX,
 *                   "battery":XX.XX,"dtcs":["PXXXX",...]}\n
 *
 * @param  rpm       : régime moteur (tr/min)
 * @param  speed     : vitesse (km/h)
 * @param  temp      : température moteur (°C)
 * @param  fuel      : niveau carburant (%)
 * @param  battery   : tension batterie (V * 100, ex: 1420 = 14.20 V)
 * @param  dtc_list  : tableau de chaînes DTC (ex: {"P0300","P0171"})
 * @param  dtc_count : nombre de DTCs valides dans dtc_list
 */
static void UART_SendJSON(uint16_t rpm,
                          uint8_t  speed,
                          int16_t  temp,
                          uint8_t  fuel,
                          uint32_t battery_raw,   /* (A*256+B) en mV */
                          uint8_t  engine_load,     /* NOUVEAU */
						  uint16_t avg_conso_raw,
                          char     dtc_list[][6],
                          uint8_t  dtc_count)
{
    char json[256];
    char dtc_part[80] = "[";

    /* ── Construction du tableau DTC ── */
    for (uint8_t i = 0; i < dtc_count && i < 3; i++)
    {
        char tmp[12];
        if (i > 0) strncat(dtc_part, ",", sizeof(dtc_part) - strlen(dtc_part) - 1);
        snprintf(tmp, sizeof(tmp), "\"%s\"", dtc_list[i]);
        strncat(dtc_part, tmp, sizeof(dtc_part) - strlen(dtc_part) - 1);
    }
    strncat(dtc_part, "]", sizeof(dtc_part) - strlen(dtc_part) - 1);

    /* ── Tension : séparer volts et centièmes ── */
    uint16_t v_int  = (uint16_t)(battery_raw / 1000);
    uint16_t v_frac = (uint16_t)((battery_raw % 1000) / 10);

    /* Consommation : séparer entier et dixième */
    uint16_t c_int  = avg_conso_raw / 10;
    uint16_t c_frac = avg_conso_raw % 10;

    snprintf(json, sizeof(json),
             "{\"rpm\":%u,\"speed\":%u,\"temp\":%d,\"fuel\":%u,"
             "\"battery\":%u.%02u,\"engine_load\":%u,"
             "\"avg_consumption\":%u.%u,\"dtcs\":%s}\n",
             rpm, speed, temp, fuel,
             v_int, v_frac,
             engine_load,
             c_int, c_frac,
             dtc_part);

    HAL_UART_Transmit(&huart2, (uint8_t *)json, (uint16_t)strlen(json), 200);
}


/* ─── Test principal MCP2515 ──────────────────────────────────── */

/**
 * @brief Effectue le test complet de communication SPI avec le MCP2515.
 *        Résultats affichés sur TeraTerm via USART2 @ 115200 baud.
 *
 * Valeurs attendues après RESET :
 *   CANSTAT = 0x80  (OPMOD = 100 = Configuration Mode)
 *   CANCTRL = 0x87  (REQOP = 100, CLKEN = 1, CLKPRE = 11)
 */
static void MCP2515_Test(void)
{
    char    buf[80];
    uint8_t canstat, canctrl, readback;
    uint8_t pass = 1; /* flag global de réussite */

    /* ── Bannière ─────────────────────────────────────────────── */
    UART_Print("\r\n");
    UART_Print("================================================\r\n");
    UART_Print("   MCP2515 SPI Test — STM32F407G-DISC1\r\n");
    UART_Print("================================================\r\n\r\n");

    /* ── Étape 1 : Reset ──────────────────────────────────────── */
    UART_Print("[1] Envoi commande RESET (0xC0)... ");
    if (MCP2515_Reset() == HAL_OK) {
        UART_Print("HAL OK\r\n");
    } else {
        UART_Print("ERREUR HAL_SPI_Transmit !\r\n");
        pass = 0;
    }

    /* ── Étape 2 : Lecture CANSTAT ────────────────────────────── */
    canstat = MCP2515_ReadRegister(MCP_CANSTAT);
    snprintf(buf, sizeof(buf), "[2] CANSTAT (0x0E) = 0x%02X  ", canstat);
    UART_Print(buf);

    if (canstat == 0x80) {
        UART_Print("=> OK  (Configuration Mode)\r\n");
    } else if (canstat == 0xFF) {
        UART_Print("=> ERREUR : MISO flottant (non connecte)\r\n");
        pass = 0;
    } else if (canstat == 0x00) {
        UART_Print("=> ERREUR : MISO bloque a 0 (verifier CS/cablage)\r\n");
        pass = 0;
    } else {
        UART_Print("=> ERREUR : valeur inattendue\r\n");
        pass = 0;
    }

    /* ── Étape 3 : Lecture CANCTRL ────────────────────────────── */
    canctrl = MCP2515_ReadRegister(MCP_CANCTRL);
    snprintf(buf, sizeof(buf), "[3] CANCTRL (0x0F) = 0x%02X  ", canctrl);
    UART_Print(buf);

    if (canctrl == 0x87) {
        UART_Print("=> OK (Config Mode, CLKEN=1, CLKPRE=/8)\r\n");
    } else {
        UART_Print("=> ERREUR : valeur inattendue (attendu 0x87)\r\n");
        pass = 0;
    }

    /* ── Étape 4 : Test écriture / relecture (CNF1) ───────────── */
    UART_Print("[4] Test ecriture/relecture CNF1 (0x2A)...\r\n");

    MCP2515_WriteRegister(MCP_CNF1, 0x42);
    HAL_Delay(1);
    readback = MCP2515_ReadRegister(MCP_CNF1);

    snprintf(buf, sizeof(buf),
             "    Ecrit : 0x42  Lu : 0x%02X  => %s\r\n",
             readback,
             (readback == 0x42) ? "OK (MOSI + MISO fonctionnels)"
                                : "ERREUR (MOSI ou MISO defaillant)");
    UART_Print(buf);
    if (readback != 0x42) pass = 0;

    /* ── Décoder CANSTAT pour information ─────────────────────── */
    UART_Print("\r\n--- Detail CANSTAT ---\r\n");
    uint8_t opmod = (canstat >> 5) & 0x07;
    const char *mode_str;
    switch (opmod) {
        case 0: mode_str = "Normal";        break;
        case 1: mode_str = "Sleep";         break;
        case 2: mode_str = "Loopback";      break;
        case 3: mode_str = "Listen-Only";   break;
        case 4: mode_str = "Configuration"; break;
        default:mode_str = "Inconnu";       break;
    }
    snprintf(buf, sizeof(buf), "    OPMOD[7:5] = %d => Mode : %s\r\n",
             opmod, mode_str);
    UART_Print(buf);

    /* ── Résultat final ───────────────────────────────────────── */
    UART_Print("\r\n================================================\r\n");
    if (pass) {
        UART_Print("   RESULTAT : [SUCCES] MCP2515 repond correctement\r\n");
    } else {
        UART_Print("   RESULTAT : [ECHEC]  Verifier cablage SPI/CS\r\n");
    }
    UART_Print("================================================\r\n");
}

/* ─── Envoi d'une requête OBD-II et lecture de la réponse ─────── */
/**
 * @brief  Envoie une requête Mode 01 pour un PID donné,
 *         attend la réponse et remplit rxMsg.
 * @param  pid     : PID OBD-II demandé (ex: 0x0C, 0x0D, 0x05)
 * @param  rxMsg   : trame de réponse remplie si succès
 * @retval 1 = réponse reçue et valide, 0 = pas de réponse
 */
static uint8_t OBD_Request(uint8_t pid, can_frame *rxMsg)
{
    can_frame txMsg;
    memset(&txMsg, 0, sizeof(txMsg));

    txMsg.can_id  = 0x7DF;  /* Broadcast OBD-II */
    txMsg.can_dlc = 8;
    txMsg.data[0] = 0x02;   /* 2 octets utiles : Mode + PID */
    txMsg.data[1] = 0x01;   /* Mode 01 : données temps réel */
    txMsg.data[2] = pid;    /* PID demandé */
    txMsg.data[3] = 0x00;
    txMsg.data[4] = 0x00;
    txMsg.data[5] = 0x00;
    txMsg.data[6] = 0x00;
    txMsg.data[7] = 0x00;
    /* data[3..7] = 0x00 (padding) */

    MCP2515_SendMessage(&txMsg);
    HAL_Delay(50);  /* Laisser le simulateur ECU répondre */

    return MCP2515_ReadMessage(rxMsg);
}

/* ─── Décodage d'un DTC OBD-II ────────────────────────────────── */
/**
 * @brief Transforme les 2 octets d'un DTC en chaîne lisible (ex: "P0300")
 */
static void DecodeDTC(uint8_t high, uint8_t low, char *out_str)
{
    const char categories[] = {'P', 'C', 'B', 'U'};
    char category = categories[high >> 6];      /* 2 bits de poids fort */
    uint8_t digit2 = (high >> 4) & 0x03;        /* 2 bits suivants */
    uint8_t digit3 = high & 0x0F;               /* 4 bits de poids faible (1er octet) */
    uint8_t digit4 = (low >> 4) & 0x0F;         /* 4 bits de poids fort (2ème octet) */
    uint8_t digit5 = low & 0x0F;                /* 4 bits de poids faible (2ème octet) */

    sprintf(out_str, "%c%d%X%X%X", category, digit2, digit3, digit4, digit5);
}

/* ─── Requête Mode 03 (DTC) ───────────────────────────────────── */
static uint8_t OBD_Request_Mode03(can_frame *rxMsg)
{
    can_frame txMsg;
    memset(&txMsg, 0, sizeof(txMsg));

    txMsg.can_id  = 0x7DF;
    txMsg.can_dlc = 8;
    txMsg.data[0] = 0x01;   /* Seulement 1 octet utile : le Mode */
    txMsg.data[1] = 0x03;   /* Mode 03 : Demande de DTCs */
    txMsg.data[2] = 0x00;
    txMsg.data[3] = 0x00;
    txMsg.data[4] = 0x00;
    txMsg.data[5] = 0x00;
    txMsg.data[6] = 0x00;
    txMsg.data[7] = 0x00;

    MCP2515_SendMessage(&txMsg);
    HAL_Delay(50);
    return MCP2515_ReadMessage(rxMsg);
}

/* ─── main ────────────────────────────────────────────────────── */

int main(void)
{
    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();
    MX_SPI1_Init();
    MX_USART2_UART_Init();

    /* USER CODE BEGIN 2 */
    HAL_Delay(200);
    MCP2515_Test();

    UART_Print("\r\n--- Initialisation du Bus CAN (500 kbps) ---\r\n");
    if (MCP2515_InitCAN()) {
        UART_Print("[SUCCES] MCP2515 en mode NORMAL. Pret a interroger le simulateur !\r\n\r\n");
    } else {
        UART_Print("[ECHEC] Impossible de configurer le mode CAN.\r\n\r\n");
    }
    /* USER CODE END 2 */

    /* ─── Boucle principale ───────────────────────────────────── */
    /* ─── Boucle principale ───────────────────────────────────── */
    while (1)
     {
         can_frame rxMsg;

         /* Valeurs par défaut (0 = "pas de réponse") */
         uint16_t rpm         = 0;
         uint8_t  speed       = 0;
         int16_t  temp        = 0;
         uint8_t  fuel        = 0;
         uint32_t battery_raw = 0;
         uint8_t  engine_load   = 0;
         uint16_t avg_consumption_raw = 0;  /* ×10, ex: 74 = 7.4 L/100km */
         char    dtc_list[3][6] = {{0}};
         uint8_t dtc_count      = 0;

         /* ── RPM (PID 0x0C) ── */
         if (OBD_Request(0x0C, &rxMsg))
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[2] == 0x0C)
                 rpm = ((rxMsg.data[3] * 256) + rxMsg.data[4]) / 4;
         HAL_Delay(100);

         /* ── Vitesse (PID 0x0D) ── */
         if (OBD_Request(0x0D, &rxMsg))
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[2] == 0x0D)
                 speed = rxMsg.data[3];
         HAL_Delay(100);

         /* ── Température (PID 0x05) ── */
         if (OBD_Request(0x05, &rxMsg))
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[2] == 0x05)
                 temp = (int16_t)rxMsg.data[3] - 40;
         HAL_Delay(100);

         /* ── Carburant (PID 0x2F) ── */
         if (OBD_Request(0x2F, &rxMsg))
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[2] == 0x2F)
                 fuel = (rxMsg.data[3] * 100) / 255;
         HAL_Delay(100);

         /* ── Tension batterie (PID 0x42) ── */
         if (OBD_Request(0x42, &rxMsg))
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[2] == 0x42)
                 battery_raw = (rxMsg.data[3] * 256) + rxMsg.data[4];
         HAL_Delay(100);
         /* ── Engine Load (PID 0x04) ── */
         if (OBD_Request(0x04, &rxMsg))
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[2] == 0x04)
                 engine_load = (rxMsg.data[3] * 100) / 255;
         HAL_Delay(100);

         /* ── Avg Fuel consumption ── */
         if (OBD_Request(0xF1, &rxMsg))
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[2] == 0xF1)
                 avg_consumption_raw = (rxMsg.data[3] * 256) + rxMsg.data[4];
         HAL_Delay(100);

         /* ── DTCs (Mode 03) ── */
         if (OBD_Request_Mode03(&rxMsg))
         {
             if (rxMsg.can_id == 0x7E8 && rxMsg.data[1] == 0x43)
             {
                 dtc_count = rxMsg.data[2];
                 if (dtc_count > 3) dtc_count = 3;   /* sécurité tableau */
                 for (uint8_t i = 0; i < dtc_count; i++)
                     DecodeDTC(rxMsg.data[3 + i*2],
                               rxMsg.data[4 + i*2],
                               dtc_list[i]);
             }
         }

         /* ── Envoi JSON vers Raspberry Pi ── */
         UART_SendJSON(rpm, speed, temp, fuel, battery_raw,
                       engine_load, avg_consumption_raw,
                       dtc_list, dtc_count);

         HAL_Delay(1500);   /* Pause 1.5 s entre deux cycles */
     }
}

/* ─── System Clock ────────────────────────────────────────────── */

/**
 * @brief Configuration horloge système à 168 MHz via PLL + HSI.
 *
 * CORRECTION : HSE_OFF avec PLL source HSE est invalide.
 * On utilise HSI (oscillateur interne 16 MHz) comme source PLL.
 * Résultat : SYSCLK = 168 MHz, APB1 = 42 MHz, APB2 = 84 MHz.
 * SPI1 (APB2=84MHz) / prescaler 16 = 5.25 MHz  ✓ (< 10 MHz max MCP2515)
 */
void SystemClock_Config(void)
{
    RCC_OscInitTypeDef RCC_OscInitStruct = {0};
    RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

    __HAL_RCC_PWR_CLK_ENABLE();
    __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE1);

    /* HSI 16 MHz → PLL → 168 MHz */
    RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI;
    RCC_OscInitStruct.HSIState       = RCC_HSI_ON;
    RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
    RCC_OscInitStruct.PLL.PLLState   = RCC_PLL_ON;
    RCC_OscInitStruct.PLL.PLLSource  = RCC_PLLSOURCE_HSI;
    /* PLLM=8 → VCO_in=2MHz | PLLN=168 → VCO_out=336MHz | PLLP=/2 → 168MHz */
    RCC_OscInitStruct.PLL.PLLM = 8;
    RCC_OscInitStruct.PLL.PLLN = 168;
    RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
    RCC_OscInitStruct.PLL.PLLQ = 7;
    if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK) Error_Handler();

    RCC_ClkInitStruct.ClockType      = RCC_CLOCKTYPE_HCLK  | RCC_CLOCKTYPE_SYSCLK
                                     | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    RCC_ClkInitStruct.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
    RCC_ClkInitStruct.AHBCLKDivider  = RCC_SYSCLK_DIV1;   /* HCLK  = 168 MHz */
    RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV4;     /* APB1  =  42 MHz */
    RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV2;     /* APB2  =  84 MHz */
    if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_5) != HAL_OK)
        Error_Handler();
}

/* ─── SPI1 Init ───────────────────────────────────────────────── */

static void MX_SPI1_Init(void)
{
    hspi1.Instance               = SPI1;
    hspi1.Init.Mode              = SPI_MODE_MASTER;
    hspi1.Init.Direction         = SPI_DIRECTION_2LINES;
    hspi1.Init.DataSize          = SPI_DATASIZE_8BIT;
    hspi1.Init.CLKPolarity       = SPI_POLARITY_LOW;   /* CPOL=0 */
    hspi1.Init.CLKPhase          = SPI_PHASE_1EDGE;    /* CPHA=0 → Mode 0 */
    hspi1.Init.NSS               = SPI_NSS_SOFT;       /* CS géré manuellement */
    hspi1.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_16; /* 84/16 = 5.25 MHz */
    hspi1.Init.FirstBit          = SPI_FIRSTBIT_MSB;
    hspi1.Init.TIMode            = SPI_TIMODE_DISABLE;
    hspi1.Init.CRCCalculation    = SPI_CRCCALCULATION_DISABLE;
    hspi1.Init.CRCPolynomial     = 10;
    if (HAL_SPI_Init(&hspi1) != HAL_OK) Error_Handler();
}

/* ─── USART2 Init ─────────────────────────────────────────────── */

static void MX_USART2_UART_Init(void)
{
    huart2.Instance          = USART2;
    huart2.Init.BaudRate     = 115200;
    huart2.Init.WordLength   = UART_WORDLENGTH_8B;
    huart2.Init.StopBits     = UART_STOPBITS_1;
    huart2.Init.Parity       = UART_PARITY_NONE;
    huart2.Init.Mode         = UART_MODE_TX_RX;
    huart2.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
    huart2.Init.OverSampling = UART_OVERSAMPLING_16;
    if (HAL_UART_Init(&huart2) != HAL_OK) Error_Handler();
}

/* ─── GPIO Init ───────────────────────────────────────────────── */

static void MX_GPIO_Init(void)
{
    GPIO_InitTypeDef GPIO_InitStruct = {0};

    /* Clocks */
    __HAL_RCC_GPIOA_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();
    __HAL_RCC_GPIOC_CLK_ENABLE();
    __HAL_RCC_GPIOD_CLK_ENABLE(); /* LEDs debug sur DISC1 */

    /* CS = HIGH par défaut (inactif) */
    HAL_GPIO_WritePin(MCP2515_CS_GPIO_Port, MCP2515_CS_Pin, GPIO_PIN_SET);

    /* INT (PC4) — entrée avec pull-up, EXTI front descendant */
    GPIO_InitStruct.Pin  = MCP2515_INT_Pin;
    GPIO_InitStruct.Mode = GPIO_MODE_IT_FALLING;
    GPIO_InitStruct.Pull = GPIO_PULLUP;
    HAL_GPIO_Init(MCP2515_INT_GPIO_Port, &GPIO_InitStruct);

    /* CS (PB6) — sortie push-pull rapide */
    GPIO_InitStruct.Pin   = MCP2515_CS_Pin;
    GPIO_InitStruct.Mode  = GPIO_MODE_OUTPUT_PP;
    GPIO_InitStruct.Pull  = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(MCP2515_CS_GPIO_Port, &GPIO_InitStruct);

    /* LEDs DISC1 : PD12 (verte), PD14 (rouge) */
    GPIO_InitStruct.Pin   = GPIO_PIN_12 | GPIO_PIN_14;
    GPIO_InitStruct.Mode  = GPIO_MODE_OUTPUT_PP;
    GPIO_InitStruct.Pull  = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(GPIOD, &GPIO_InitStruct);

    /* Éteindre les LEDs au démarrage */
    HAL_GPIO_WritePin(GPIOD, GPIO_PIN_12 | GPIO_PIN_14, GPIO_PIN_RESET);
}

/* ─── Error Handler ───────────────────────────────────────────── */

void Error_Handler(void)
{
    __disable_irq();
    /* LED rouge clignotante pour signaler une erreur fatale */
    while (1)
    {
        HAL_GPIO_TogglePin(GPIOD, GPIO_PIN_14);
        /* Busy-wait ~200ms sans HAL_Delay (SysTick peut être désactivé) */
        for (volatile uint32_t i = 0; i < 1000000; i++);
    }
}

#ifdef USE_FULL_ASSERT
void assert_failed(uint8_t *file, uint32_t line)
{
    (void)file; (void)line;
}
#endif
