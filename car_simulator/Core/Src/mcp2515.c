/* mcp2515.c */
#include "mcp2515.h"

/* ── Reset matériel du MCP2515 ── */
HAL_StatusTypeDef MCP2515_Reset(void)
{
    uint8_t cmd = MCP_RESET;
    HAL_StatusTypeDef status;

    MCP2515_CS_LOW();
    status = HAL_SPI_Transmit(&hspi1, &cmd, 1, HAL_MAX_DELAY);
    MCP2515_CS_HIGH();

    HAL_Delay(10); // Laisser le MCP2515 se réinitialiser
    return status;
}

/* ── Lecture d'un registre ── */
uint8_t MCP2515_ReadRegister(uint8_t address)
{
    uint8_t tx[3] = { MCP_READ, address, 0xFF };
    uint8_t rx[3] = { 0, 0, 0 };

    MCP2515_CS_LOW();
    HAL_SPI_TransmitReceive(&hspi1, tx, rx, 3, HAL_MAX_DELAY);
    MCP2515_CS_HIGH();

    return rx[2]; // L'octet de donnée est le 3ème
}

/* ── Écriture d'un registre ── */
HAL_StatusTypeDef MCP2515_WriteRegister(uint8_t address, uint8_t value)
{
    uint8_t tx[3] = { MCP_WRITE, address, value };
    HAL_StatusTypeDef status;

    MCP2515_CS_LOW();
    status = HAL_SPI_Transmit(&hspi1, tx, 3, HAL_MAX_DELAY);
    MCP2515_CS_HIGH();

    return status;
}

/* ── Lecture du status byte (instruction spéciale) ── */
uint8_t MCP2515_ReadStatus(void)
{
    uint8_t tx[2] = { MCP_READ_STATUS, 0xFF };
    uint8_t rx[2] = { 0, 0 };

    MCP2515_CS_LOW();
    HAL_SPI_TransmitReceive(&hspi1, tx, rx, 2, HAL_MAX_DELAY);
    MCP2515_CS_HIGH();

    return rx[1];
}

/* ── Initialisation du mode CAN (500 kbps @ Quartz 8MHz) ── */
uint8_t MCP2515_InitCAN(void)
{
    MCP2515_Reset(); // Force le mode Configuration

    // Configuration du Baud Rate à 500 kbps
    MCP2515_WriteRegister(MCP_CNF1, 0x00);
    MCP2515_WriteRegister(MCP_CNF2, 0x90);
    MCP2515_WriteRegister(MCP_CNF3, 0x02);

    // Désactiver les filtres pour recevoir tous les messages (RXB0 et RXB1)
    MCP2515_WriteRegister(0x60, 0x60); // RXB0CTRL : receive all
    MCP2515_WriteRegister(0x70, 0x60); // RXB1CTRL : receive all

    // Passer en mode NORMAL
    MCP2515_WriteRegister(MCP_CANCTRL, 0x00);
    HAL_Delay(10);

    // Vérification
    if ((MCP2515_ReadRegister(MCP_CANSTAT) & 0xE0) == 0x00) {
        return 1; // Succès
    }
    return 0; // Échec
}

/* ── Envoi d'une trame CAN ── */
uint8_t MCP2515_SendMessage(can_frame *frame)
{
    // Écriture de l'ID (Trame standard 11 bits) dans le buffer TXB0
    MCP2515_WriteRegister(0x31, (uint8_t)(frame->can_id >> 3));        // TXB0SIDH
    MCP2515_WriteRegister(0x32, (uint8_t)((frame->can_id & 0x07) << 5)); // TXB0SIDL
    MCP2515_WriteRegister(0x33, 0x00); // EID8
    MCP2515_WriteRegister(0x34, 0x00); // EID0
    MCP2515_WriteRegister(0x35, frame->can_dlc); // DLC

    // Écriture des données
    for(int i = 0; i < frame->can_dlc; i++) {
        MCP2515_WriteRegister(0x36 + i, frame->data[i]);
    }

    // Commande Request-To-Send pour TXB0 (0x81)
    uint8_t rts = 0x81;
    MCP2515_CS_LOW();
    HAL_SPI_Transmit(&hspi1, &rts, 1, 100);
    MCP2515_CS_HIGH();

    return 1;
}

/* ── Lecture d'une trame CAN ── */
uint8_t MCP2515_ReadMessage(can_frame *frame)
{
    uint8_t status = MCP2515_ReadStatus();

    if (status & 0x01) { // Un message est disponible dans le buffer RXB0
        // Lecture de l'ID
        uint8_t sidh = MCP2515_ReadRegister(0x61); // RXB0SIDH
        uint8_t sidl = MCP2515_ReadRegister(0x62); // RXB0SIDL
        frame->can_id = (sidh << 3) | (sidl >> 5);

        // Lecture du DLC
        frame->can_dlc = MCP2515_ReadRegister(0x65) & 0x0F;

        // Lecture des données
        for(int i = 0; i < frame->can_dlc; i++) {
            frame->data[i] = MCP2515_ReadRegister(0x66 + i);
        }

        // Effacer le drapeau d'interruption (Libérer le buffer RXB0)
        uint8_t bit_modify[4] = { 0x05, 0x2C, 0x01, 0x00 }; // 0x2C = CANINTF
        MCP2515_CS_LOW();
        HAL_SPI_Transmit(&hspi1, bit_modify, 4, 100);
        MCP2515_CS_HIGH();

        return 1; // Message lu avec succès
    }
    return 0; // Aucun message
}
