const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const PartialTrade = buildModule("BlockAISwapPartial", (m) => {
    const contract = m.contract("BlockAISwapPartial", ["0x10ED43C718714eb63d5aA57B78B54704E256024E", "0x1b81D678ffb9C0263b24A97847620C99d213eB14"]);

    return { contract };
});

module.exports = PartialTrade;