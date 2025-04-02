const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const PartialTrade = buildModule("BlockAISwapPartial", (m) => {
    const contract = m.contract("BlockAISwapPartial", ["0x327Df1E6de05895d2ab08513aaDD9313Fe505d86", "0x1B8eea9315bE495187D873DA7773a874545D9D48"]);

    return { contract };
});

module.exports = PartialTrade;