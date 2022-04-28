
from scripts.deploy_utils import *

Accs = setup_mainnet_accounts()

RVRS = "0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE"
VERVRS = "0x9520E7d6eD2256613C30B22b566259aefcA7D75D"
DUMMY_TOKEN = "0xe17f05ae533e9B69C89d4EfE067Bd71fd7232182"
AUTO_RVRS = "0x0b075c7F350E0E844d76dFDe4D4c816a365dC879"
MASTERCHEF = "0xeEA71889c062c135014Ec34825a1958c87A2Ac61"
multisig = "0xA3904e99b6012EB883DB1090D02D4e954539EC61"

rvrs = Contract.from_abi("ReverseToken", RVRS, abi=ReverseToken.abi)
ve_rvrs = Contract.from_abi("VeRvrs", VERVRS, abi=VeRvrs.abi)
dummy_token = Contract.from_abi("DummyToken", DUMMY_TOKEN, abi=veRvrsRewards.abi)
auto_rvrs = Contract.from_abi("AutoRvrs", AUTO_RVRS, abi=AutoRvrs.abi)
chef = Contract.from_abi("CoffinMakerV2", MASTERCHEF, abi=CoffinMakerV2.abi)
chef_pid = 4

# dummy_token = veRvrsRewards.deploy(Accs.from_deployer())
# dummy_token.mint(Accs.deployer, 1)
# resp = chef.addPool(0, dummy_token, 0, 0, 0, False, Accs.from_deployer())
#
# chef_pid = 4
# print(f"Dummy token added to pool id = {chef_pid}")
# assert chef.poolInfo(4)[0] == dummy_token, "Bad pool id!"
#
# ve_rvrs = VeRvrs.deploy(Accs.from_deployer())
# ve_rvrs.initialize(rvrs, chef, multisig, chef_pid, Accs.from_deployer())
