const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const TokenA = buildModule("ERC20_CUSTOM", (m) => {
    const token = m.contract("ERC20_CUSTOM", ["AToken", "AT"]);

    return { token };
});

module.exports = TokenA;