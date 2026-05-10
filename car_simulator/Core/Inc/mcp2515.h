/* mcp2515.h */
#ifndef MCP2515_H_
#define MCP2515_H_

#include "stm32f4xx_hal.h"

#define MCP2515_CS_LOW()   HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_RESET)
#define MCP2515_CS_HIGH()  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_SET)

/* Instructions SPI MCP2515 */
#define MCP_READ         0x03
#define MCP_WRITE        0x02
#define MCP_RESET        0xC0
#define MCP_READ_STATUS  0xA0
#define MCP_LOOPBACK    0x40
/* Adresses des registres */
#define MCP_CANSTAT      0x0E
#define MCP_CANCTRL      0x0F
#define MCP_CNF1         0x2A
#define MCP_CNF2         0x29
#define MCP_CNF3         0x28

/* --- Structure de la trame CAN --- */
typedef struct {
    uint32_t can_id;
    uint8_t  can_dlc;
    uint8_t  data[8];
} can_frame;

/* --- Prototypes des fonctions pour les rendre visibles --- */
HAL_StatusTypeDef MCP2515_Reset(void);
uint8_t MCP2515_ReadRegister(uint8_t address);
HAL_StatusTypeDef MCP2515_WriteRegister(uint8_t address, uint8_t value);
uint8_t MCP2515_ReadStatus(void);
uint8_t MCP2515_InitCAN(void);
uint8_t MCP2515_SendMessage(can_frame *frame);
uint8_t MCP2515_ReadMessage(can_frame *frame);


extern SPI_HandleTypeDef hspi1;
#endif
