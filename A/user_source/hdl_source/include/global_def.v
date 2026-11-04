`define DATA_WIDTH 32
`define ADDR_WIDTH 21
`define DM_WIDTH 4
`define ROW_WIDTH 11
`define BA_WIDTH 2
// This macro is substituted inside other arithmetic expressions.
`define SDR_CLK_PERIOD (1000000000 / 50000000)
// Nominal 32 ms per 2048-row sweep leaves 32 ms of retention margin for
// controller arbitration and pending application bursts.
`define SELF_REFRESH_INTERVAL (32000000 / `SDR_CLK_PERIOD / (2 ** `ROW_WIDTH))
