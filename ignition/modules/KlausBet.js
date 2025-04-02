const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const KlausBet = buildModule("KlausBet", (m) => {
    const klausbet = m.contract("KlausBet", ["0x57BF6a0B74A8f6c61f90bff43D8Cd4c2d7a27a2a", "0x3DfD1B0BABfc7110520575dA8230389C36C32Ca6"]);

    return { klausbet };
});

module.exports = KlausBet;