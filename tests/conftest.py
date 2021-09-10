import pytest
from brownie import config

fixtures = "currency", "whale", "stakePool"
params = [
    pytest.param(
        "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        "0xFE176A2b1e1F67250d2903B8d25f56C0DaBcd6b2",
        "0x9F7968de728aC7A6769141F63dCA03FD8b03A76F",
        id="NYAN ETH farm",
    ),
]


@pytest.fixture
def andre(accounts):
    # Andre, giver of tokens, and maker of yield
    yield accounts[0]


@pytest.fixture
def gov(accounts):
    # yearn multis... I mean YFI governance. I swear!
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    # YFI Whale, probably
    yield accounts[2]


@pytest.fixture
def strategist(accounts):
    # You! Our new Strategist!
    yield accounts[3]


@pytest.fixture
def keeper(accounts):
    # This is our trusty bot!
    yield accounts[4]


@pytest.fixture
def bob(accounts):
    yield accounts[5]


@pytest.fixture
def alice(accounts):
    yield accounts[6]


@pytest.fixture
def rewards(gov):
    yield gov  # TODO: Add rewards contract


@pytest.fixture
def currency(request, interface):
    # this one is 3EPS
    yield interface.ERC20(request.param)


@pytest.fixture
def whale(request, accounts):
    acc = accounts.at(request.param, force=True)
    yield acc


@pytest.fixture
def stakePool(request):
    yield request.param


@pytest.fixture
def vault(pm, gov, rewards, guardian, currency):
    Vault = pm(config["dependencies"][0]).Vault
    vault = gov.deploy(Vault)
    vault.initialize(currency.address, gov, rewards, "", "", guardian)
    vault.setManagementFee(0, {"from": gov})
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, Strategy, stakePool):
    strategy = strategist.deploy(Strategy, vault, stakePool)
    strategy.setKeeper(keeper)
    yield strategy
