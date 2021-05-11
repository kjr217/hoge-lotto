import brownie
import pytest
import constants


# 217

def test_start_lotto(lotto_contract, accounts):
    tx = lotto_contract.startLotto({"from": accounts[0]})
    assert lotto_contract.nextLottoId() == 1
    assert "LottoStarted" in tx.events


def test_enter(lotto_contract, accounts, token):
    bal = 0
    lotto_contract.startLotto({"from": accounts[0]})
    lotto_id = lotto_contract.nextLottoId() - 1
    for account in accounts[1:]:
        token.approve(lotto_contract.address, constants.INITIAL_BALANCE, {"from": account})
        tx = lotto_contract.enter(token.balanceOf(account), lotto_id, {"from": account})
        assert "Entered" in tx.events
        bal += lotto_contract.stakeOf(account, lotto_id)
    # run brownie test -s to see stake proportions
    for n, account in enumerate(accounts[1:]):
        print("STAKE OF ACCOUNT " +
              str(n+1) + " :" +
              str(lotto_contract.stakeOf(account, lotto_id) / lotto_contract.totalAmount(lotto_id)))
    assert lotto_contract.totalAmount(lotto_id) == bal


def test_conclude_succeeds(lotto_contract, accounts, token, vrf_coordinator):
    lotto_contract.startLotto({"from": accounts[0]})
    lotto_id = lotto_contract.nextLottoId() - 1
    for account in accounts[1:]:
        token.approve(lotto_contract.address, constants.INITIAL_BALANCE, {"from": account})
        lotto_contract.enter(token.balanceOf(account), lotto_id, {"from": account})
    request_id = lotto_contract.requestRandomNumber({"from": accounts[0]}).return_value
    vrf_coordinator.callBackWithRandomness(
        request_id, 420, lotto_contract.address, {"from": accounts[0]}
    )
    assert lotto_contract.randomResult() > 0
    tx = lotto_contract.concludeLotto(lotto_id, {"from": accounts[0]})
    assert "WinnerAnnounced" in tx.events
    assert tx.events["WinnerAnnounced"]["winner"] == lotto_contract.winner(lotto_id)
    assert lotto_contract.isConcluded(lotto_id)
    winner = tx.events["WinnerAnnounced"]["winner"]
    winner_bal_bef = token.balanceOf(winner)
    lotto_contract.claimWinnings(lotto_id, {"from": winner})
    assert lotto_contract.isWinningClaimed(lotto_id)
    assert winner_bal_bef < token.balanceOf(winner) <(lotto_contract.totalAmount(lotto_id) * 8500)/10000
    assert not lotto_contract.isCutClaimed(lotto_id)
    bal_bef = token.balanceOf(accounts[0])
    lotto_contract.claimHogeCut(lotto_id, {"from": accounts[0]})
    assert lotto_contract.isCutClaimed(lotto_id)
    assert bal_bef < token.balanceOf(accounts[0]) < bal_bef + (lotto_contract.totalAmount(lotto_id) * 1500)/10000


def test_conclude_fails_with_no_rng(lotto_contract, accounts, token, vrf_coordinator):
    lotto_contract.startLotto({"from": accounts[0]})
    lotto_id = lotto_contract.nextLottoId() - 1
    for account in accounts[1:]:
        token.approve(lotto_contract.address, constants.INITIAL_BALANCE, {"from": account})
        lotto_contract.enter(token.balanceOf(account), lotto_id, {"from": account})
    lotto_contract.requestRandomNumber({"from": accounts[0]})
    with brownie.reverts("concludeLotto: random number not returned yet"):
        lotto_contract.concludeLotto(lotto_id, {"from": accounts[0]})


def test_conclude_show_winners(lotto_contract, accounts, token, vrf_coordinator):
    for n in range(10):
        lotto_contract.startLotto({"from": accounts[0]})
        lotto_id = lotto_contract.nextLottoId() - 1
        for account in accounts[1:]:
            token.approve(lotto_contract.address, constants.INITIAL_BALANCE, {"from": account})
            lotto_contract.enter(token.balanceOf(account)/50, lotto_id, {"from": account})
        request_id = lotto_contract.requestRandomNumber({"from": accounts[0]}).return_value
        vrf_coordinator.callBackWithRandomness(
            request_id, 420, lotto_contract.address, {"from": accounts[0]}
        )
        assert lotto_contract.randomResult() > 0
        tx = lotto_contract.concludeLotto(lotto_id, {"from": accounts[0]})
        assert "WinnerAnnounced" in tx.events
        assert tx.events["WinnerAnnounced"]["winner"] == lotto_contract.winner(lotto_id)
        # run brownie test -s to see winners
        print("Winner of lotto " + str(n) + " :" + str(lotto_contract.winner(lotto_id)))
