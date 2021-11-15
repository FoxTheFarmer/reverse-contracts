
from build.deployments.deploy_utils import setup_mainnet_accounts

Accs = setup_mainnet_accounts()

INITIAL_MINT_AMOUNT = 7025000

rvrs = ReverseToken.deploy({'from': Accs.deployer})

resp = rvrs.mint(Accs.deployer, int(INITIAL_MINT_AMOUNT*1e18), {'from': Accs.deployer})

