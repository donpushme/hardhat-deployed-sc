const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const TokenB = buildModule("ERC20_CUSTOM", (m) => {
    const token = m.contract("ERC20_CUSTOM", ["BToken", "BT"]);

    return { token };
});

module.exports = TokenB;