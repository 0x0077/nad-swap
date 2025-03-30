#pragma version 0.4.0

from ethereum.ercs import IERC20

interface IPoolMaster:
    def notify_fees(_fee_type: uint16, _token: address, _amount: uint256, _fee_rate: uint256, _data: Bytes[1_024]): nonpayable

interface IFlashLoanRecipient:
    def receiveFlashLoan(
        _tokens: DynArray[address, max_value(uint8)],
        _amounts: DynArray[uint256, max_value(uint8)],
        _fee_amounts: DynArray[uint256, max_value(uint8)],
        user_data: Bytes[1_024]
    ): nonpayable

interface IERC3156FlashBorrower:
    def onFlashLoan(_initiator: address, _token: address, _amount: uint256, _fee: uint256, _data: Bytes[1_024]) -> bytes32: nonpayable

interface IWETH:
    def deposit(): payable
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
    def withdraw(_value: uint256): nonpayable

event FlashLoanFeePercentageChanged:
    oldFlashLoanFeePercentage: uint256
    newFlashLoanFeePercentage: uint256

event FlashLoan:
    recipient: indexed(address)
    token: indexed(address)
    amount: indexed(uint256)
    received_fee_amount: uint256

event Kill:
    account: address

ERC3156_CALLBACK_SUCCESS: public(constant(bytes32)) = keccak256("ERC3156FlashBorrower.onFlashLoan")
_MAX_PROTOCOL_FLASH_LOAN_FEE_PERCENTAGE: constant(uint256) = 10 ** 17 # 10%
NATIVE_ETH: constant(address) = empty(address)

flash_loan_fee_percentage: public(uint256)
flash_loan_fee_recipient: public(address) # self

wETH: public(immutable(address))

balances: HashMap[address, HashMap[address, uint256]]
reserves: public(HashMap[address, uint256])

owner: public(address)
is_kill: public(bool)


@deploy 
@payable 
def __init__(_weth: address):
    assert msg.sender != empty(address), "INVALID_FLASH_LOAN_FEE_RECIPIENT"

    self.flash_loan_fee_percentage = 5 * 10 ** 14 # 0.05%
    self.flash_loan_fee_recipient = msg.sender

    wETH = _weth
    self.owner = msg.sender


@payable 
@external
def __default__():
    if msg.sender != wETH:
        self._deposit(NATIVE_ETH, msg.sender, msg.value) 


@view 
@internal 
def _calculate_flash_loan_fee_amount(_amount: uint256) -> uint256:
    return _amount * self.flash_loan_fee_percentage // (10 ** 18)


@internal
def _safe_transfer(_token: address, _to: address, _amount: uint256):
    response: Bytes[32] = b""
    success: bool = False
    success, response = raw_call(
        _token,
        abi_encode(
            _to,
            _amount,
            method_id=method_id("transfer(address,uint256)")
        ),
        max_outsize=32,
        revert_on_failure=False
    )

    assert success and (len(response) > 0 and convert(response, bool)), "Transfer failed"


@internal 
def _safe_transfer_from(_token: address, _from: address, _to: address, _amount: uint256):
    response: Bytes[32] = b""
    success: bool = False
    success, response = raw_call(
        _token,
        abi_encode(
            _from,
            _to,
            _amount,
            method_id=method_id("transferFrom(address,address,uint256)")
        ),
        max_outsize=32,
        revert_on_failure=False
    )

    assert success and (len(response) > 0 and convert(response, bool)), "Transfer failed"


@internal 
def _safe_transfer_eth(_to: address, _amount: uint256):
    success: bool = raw_call(_to, b"", value=_amount, revert_on_failure=False)
    assert success, "ETH transfer failed"


@internal 
def _pay_fee_amount(_token: address, _amount: uint256):
    if _amount != 0:
        _flash_loan_fee_recipient: address = self.flash_loan_fee_recipient
        self._safe_transfer(_token, _flash_loan_fee_recipient, _amount)
        extcall IPoolMaster(_flash_loan_fee_recipient).notify_fees(10, _token, _amount, self.flash_loan_fee_percentage, b"")


@internal
def _deposit(_token: address, _to: address, _amount: uint256) -> uint256:
    amount: uint256 = empty(uint256)
    token: address = _token
    if token == NATIVE_ETH:
        amount = _amount
    else:
        assert _amount == 0

        if token == wETH:
            token = NATIVE_ETH
            amount = staticcall IERC20(wETH).balanceOf(self)
            extcall IWETH(wETH).withdraw(amount)
        else:
            amount = staticcall IERC20(token).balanceOf(self) - self.reserves[token]
    
    self.reserves[token] += amount
    self.balances[token][_to] += amount

    return amount


@internal 
def _wrap_and_transfer_weth(_to: address, _amount: uint256):
    extcall IWETH(wETH).deposit(value=_amount)
    extcall IWETH(wETH).transfer(_to, _amount)


@view 
@external 
def balanceOf(_token: address, _account: address) -> uint256:
    token: address = _token
    if token == wETH:
        token = NATIVE_ETH
    return self.balances[token][_account]


@view
@external 
def max_flash_loan(_token: address) -> uint256:
    return staticcall IERC20(_token).balanceOf(self)


@view 
@external 
def flash_fee(_token: address, _amount: uint256) -> uint256:
    return self._calculate_flash_loan_fee_amount(_amount)


@external 
def set_flash_loan_fee_percentage(_new_flash_loan_fee_percentage: uint256):
    assert msg.sender == self.owner, "Invalid address"
    assert _new_flash_loan_fee_percentage <= _MAX_PROTOCOL_FLASH_LOAN_FEE_PERCENTAGE, "FLASH_LOAN_FEE_PERCENTAGE_TOO_HIGH"
    log FlashLoanFeePercentageChanged(self.flash_loan_fee_percentage, _new_flash_loan_fee_percentage)
    self.flash_loan_fee_percentage = _new_flash_loan_fee_percentage


@external 
def set_flash_loan_fee_recipient(_flash_loan_fee_recipient: address):
    assert msg.sender == self.owner, "Invalid address"
    assert _flash_loan_fee_recipient != empty(address), "INVALID_FLASH_LOAN_FEE_RECIPIENT"

    self.flash_loan_fee_recipient = _flash_loan_fee_recipient


@external
@nonreentrant
def flash_loan_multiple(
    _recipient: IFlashLoanRecipient, 
    _tokens: DynArray[address, max_value(uint8)], 
    _amounts: DynArray[uint256, max_value(uint8)],
    _user_data: Bytes[1_024]
):
    assert not self.is_kill, "Kill"

    tokens_length: uint256 = len(_tokens)
    assert tokens_length == len(_amounts), "INPUT_LENGTH_MISMATCH"

    fee_amounts: DynArray[uint256, max_value(uint8)] = []
    pre_loan_balances: DynArray[uint256, max_value(uint8)] = []
    previous_token: address = empty(address)
    n: uint256 = empty(uint256)
    token: address = empty(address)
    amount: uint256 = empty(uint256)

    for i: uint256 in range(255):
        if i >= tokens_length:
            break

        token = _tokens[i]
        amount = _amounts[i]
        if token == empty(address):
            assert convert(token, uint256) > convert(previous_token, uint256), "ZERO_TOKEN"
        else:
            assert convert(token, uint256) > convert(previous_token, uint256), "UNSORTED_TOKENS"

        previous_token = token

        pre_loan_balances[i] = staticcall IERC20(token).balanceOf(self)
        fee_amounts[i] = self._calculate_flash_loan_fee_amount(amount)
        
        assert pre_loan_balances[i] >= amount, "INSUFFICIENT_FLASH_LOAN_BALANCE"
        self._safe_transfer(token, _recipient.address, amount)

    extcall _recipient.receiveFlashLoan(_tokens, _amounts, fee_amounts, _user_data)

    pre_loan_balance: uint256 = empty(uint256)
    post_loan_balance: uint256 = empty(uint256)
    received_fee_amount: uint256 = empty(uint256)

    for i: uint256 in range(255):
        if i>= tokens_length:
            break
        
        token = _tokens[i]
        pre_loan_balance = pre_loan_balances[i]
        post_loan_balance = staticcall IERC20(token).balanceOf(self)
        assert post_loan_balance >= pre_loan_balance, "INVALID_POST_LOAN_BALANCE"

        received_fee_amount = post_loan_balance - pre_loan_balance
        assert received_fee_amount >= fee_amounts[i], "INSUFFICIENT_FLASH_LOAN_FEE_AMOUNT"

        self._pay_fee_amount(token, received_fee_amount)
        log FlashLoan(_recipient.address, token, _amounts[i], received_fee_amount)


@external 
@nonreentrant 
def flash_loan(_receiver: IERC3156FlashBorrower, _token: address, _amount: uint256, _user_data: Bytes[1_024]) -> bool:
    pre_loan_balance: uint256 = staticcall IERC20(_token).balanceOf(self)
    fee_amount: uint256 = self._calculate_flash_loan_fee_amount(_amount)
    assert pre_loan_balance >= _amount, "INSUFFICIENT_FLASH_LOAN_BALANCE"

    self._safe_transfer(_token, _receiver.address, _amount)
    assert extcall _receiver.onFlashLoan(msg.sender, _token, _amount, fee_amount, _user_data) == ERC3156_CALLBACK_SUCCESS, "IERC3156_CALLBACK_FAILED"

    post_loan_balance: uint256 = staticcall IERC20(_token).balanceOf(self)
    assert post_loan_balance >= pre_loan_balance, "INVALID_POST_LOAN_BALANCE"

    received_fee_amount: uint256 = post_loan_balance - pre_loan_balance
    assert received_fee_amount >= fee_amount, "INSUFFICIENT_FLASH_LOAN_FEE_AMOUNT" 

    self._pay_fee_amount(_token, received_fee_amount)
    
    log FlashLoan(_receiver.address, _token, _amount, received_fee_amount)
    return True


@payable
@external 
def deposit(_token: address, _to: address) -> uint256:
    return self._deposit(_token, _to, msg.value)


@payable 
@external 
@nonreentrant
def deposit_eth(_to: address) -> uint256:
    amount: uint256 = msg.value
    self.reserves[NATIVE_ETH] += amount
    self.balances[NATIVE_ETH][_to] += amount

    return amount


@payable 
@external 
@nonreentrant
def transfer_and_deposit(_token: address, _to: address, _amount: uint256) -> uint256:
    amount: uint256 = empty(uint256)
    token: address = _token
    if token == NATIVE_ETH:
        assert _amount == msg.value
    else:
        assert msg.value == 0

        if token == wETH:
            token = NATIVE_ETH
            extcall IWETH(wETH).transferFrom(msg.sender, self, _amount)
            extcall IWETH(wETH).withdraw(_amount)
        else:
            self._safe_transfer_from(token, msg.sender, self, _amount)
            amount = staticcall IERC20(token).balanceOf(self) - self.reserves[token]

    self.reserves[token] += amount
    self.balances[token][_to] += amount

    return amount


@external 
@nonreentrant 
def transfer(_token: address, _to: address, _amount: uint256):
    token: address = empty(address)
    if _token == wETH:
        token = NATIVE_ETH
    
    self.balances[token][msg.sender] -= _amount
    self.balances[token][_to] += _amount


@external 
@nonreentrant
def withdraw(_token: address, _to: address, _amount: uint256):
    token: address = _token
    if token == NATIVE_ETH:
        self._safe_transfer_eth(_to, _amount)
    else:
        if token == wETH:
            token = NATIVE_ETH
            self._wrap_and_transfer_weth(_to, _amount)
        else:
            self._safe_transfer(token, _to, _amount)

    self.balances[token][msg.sender] -= _amount
    self.reserves[token] -= _amount


# withdraw with mode: default=0 unwrapped=1 wrapped=2
@external 
@nonreentrant
def withdraw_alternative(_token: address, _to: address, _amount: uint256, _mode: uint8):
    token: address = _token
    if token == NATIVE_ETH:
        if _mode == 2:
            self._wrap_and_transfer_weth(_to, _amount)
        else:
            self._safe_transfer_eth(_to, _amount)
    else:
        if token == wETH:
            token = NATIVE_ETH
            
            if _mode == 1:
                self._safe_transfer_eth(_to, _amount)
            else:
                self._wrap_and_transfer_weth(_to, _amount)
        else:
            self._safe_transfer(token, _to, _amount)

    self.balances[token][msg.sender] -= _amount
    self.reserves[token] -= _amount


@external 
@nonreentrant
def withdraw_eth(_to: address, _amount: uint256):
    self._safe_transfer_eth(_to, _amount)
    self.balances[NATIVE_ETH][msg.sender] -= _amount
    self.reserves[NATIVE_ETH] -= _amount


@external
def set_kill(_kill: bool):
    assert msg.sender == self.owner, "Invalid address"
    
    self.is_kill = _kill
    log Kill(msg.sender)