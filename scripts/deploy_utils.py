
from brownie import accounts, interface, Contract
from brownie.network.account import LocalAccount
from dataclasses import dataclass


@dataclass
class Accounts:
    deployer: LocalAccount
    dev: LocalAccount
    user1: LocalAccount = None
    user2: LocalAccount = None
    user3: LocalAccount = None

    def from_deployer(self, gas=None, allow_revert=False):
        output = {'from': self.deployer}
        if gas:
            output['gas'] = gas
        if allow_revert:
            output['allow_revert'] = allow_revert
        return output

    def from_dev(self, gas=None, allow_revert=False):
        output = {'from': self.dev}
        if gas:
            output['gas'] = gas
        if allow_revert:
            output['allow_revert'] = allow_revert
        return output


def setup_mainnet_accounts(deployer_only=True):
    deployer = dev = accounts.load('revdep')
    if not deployer_only:
        dev = accounts.load('mainnet-dev')
    return Accounts(deployer, dev)


def send(coin, amt, to_, from_):
    return interface.IERC20(coin).transfer(to_, amt, {'from': from_})


def approve(coin, spender, from_, amt=1e27):
    return interface.IERC20(coin).approve(spender, int(amt), {'from': from_})


def balanceOf(coin, acc):
    return interface.IERC20(coin).balanceOf(acc)
