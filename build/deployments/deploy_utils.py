
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


def setup_mainnet_accounts():
    accounts.load('revdep')
    accounts.load('mainnet-dev')
    return Accounts(accounts[0], accounts[1])


def send(coin, amt, to_, from_):
    return interface.IERC20(coin).transfer(to_, amt, {'from': from_})


def approve(coin, spender, from_, amt=1e27):
    return interface.IERC20(coin).approve(spender, int(amt), {'from': from_})


def balanceOf(coin, acc):
    return interface.IERC20(coin).balanceOf(acc)
