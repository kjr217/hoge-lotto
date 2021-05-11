import pytest
import brownie
import random
import constants
from brownie import Contract
from brownie import (
    HogeLotto,
    HOGE,
    LinkToken,
    VRFCoordinatorMock,
    VRFConsumer,
    UniformRandomNumber,
    SortitionSumTreeFactory
)

# 217

# Network: Mainnet
# Chainlink VRF Coordinator address: 0xf0d54349aDdcf704F77AE15b96510dEA15cb7952
# LINK token address: 0x514910771af9ca656af840dff83e8264ecf986ca
# KeyHash: 0xAA77729D3466CA35AE8D28B3BBAC7CC36A5031EFDC430821C02BC31A238AF445

@pytest.fixture(scope="function", autouse=True)
def isolate_func(fn_isolation):
    # perform a chain rewind after completing each test, to ensure proper isolation
    # https://eth-brownie.readthedocs.io/en/v1.10.3/tests-pytest-intro.html#isolation-fixtures
    pass


@pytest.fixture(scope="module")
def lotto_contract(accounts, link_token, vrf_coordinator, chainlink_fee, token):
    lotto_contract = HogeLotto.deploy(0, vrf_coordinator.address, link_token.address, token.address, {"from": accounts[0]})
    link_token.transfer(lotto_contract.address, chainlink_fee*100,  {"from": accounts[0]})
    yield lotto_contract


@pytest.fixture(scope="module")
def token(accounts):
    token = HOGE.deploy({"from": accounts[0]})
    for account in accounts:
        token.transfer(account, constants.INITIAL_BALANCE, {"from": accounts[0]})
    yield token


@pytest.fixture(scope="module")
def link_token(accounts):
    link_token = LinkToken.deploy({"from": accounts[0]})
    yield link_token


@pytest.fixture(scope="module")
def vrf_coordinator(link_token, accounts):
    vrf_coordinator = VRFCoordinatorMock.deploy(
        link_token.address, {"from": accounts[0]}
    )
    yield vrf_coordinator


@pytest.fixture(scope="module")
def chainlink_fee():
    return 2e18


@pytest.fixture(scope="module")
def expiry_time():
    return 300
