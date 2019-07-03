import 'package:blaise_wallet_flutter/service_locator.dart';
import 'package:blaise_wallet_flutter/util/vault.dart';
import 'package:meta/meta.dart';
import 'package:mobx/mobx.dart';
import 'package:pascaldart/pascaldart.dart';
import 'package:logger/logger.dart';

part 'account.g.dart';

class Account = AccountBase with _$Account;

/// State for a specific account
abstract class AccountBase with Store {
  Logger log = Logger();

  @observable
  bool operationsLoading = true;

  @observable
  RPCClient rpcClient;

  @observable
  PascalAccount account;

  @observable
  List<PascalOperation> operations;

  AccountBase({@required this.rpcClient, @required this.account});

  @action
  Future<bool> updateAccount() async {
    // Update account information via getaccount, return false is unsuccessful true otherwise
    GetAccountRequest request = GetAccountRequest(account: this.account.account.account);
    RPCResponse resp = await this.rpcClient.makeRpcRequest(request);
    if (resp.isError) {
      return false;
    }
    PascalAccount updatedAccount = resp;
    this.account = updatedAccount;
    return true;
  }

  @action
  Future<void> getAccountOperations() async {
    GetAccountOperationsRequest request =
        GetAccountOperationsRequest(account: account.account.account,
                                    start: -1);
    RPCResponse resp = await this.rpcClient.makeRpcRequest(request);
    if (resp.isError) {
      ErrorResponse err = resp;
      log.e("getaccountoperations resulted in error ${err.errorMessage}");
      return null;
    }
    OperationsResponse opResp = resp;
    if (this.operations == null) {
      this.operations = opResp.operations;
    } else {
      // Diff and update operations
      this.operations.addAll(opResp.operations.where((op) => !this.operations.contains(op)));
      this.operations.sort((a, b) => b.time.compareTo(a.time));
    }
    this.operationsLoading = false;
  }

  @action
  Future<RPCResponse> doSend({@required String amount, @required String destination, String payload = ""}) async {
    // Construct send
    TransactionOperation op = TransactionOperation(
      sender: this.account.account,
      target: AccountNumber(destination),
      amount: Currency(amount)
    )
    ..withNOperation(this.account.nOperation + 1)
    ..withPayload(PDUtil.stringToBytesUtf8(payload))
    ..withFee(Currency('0'))
    ..sign(PrivateKeyCoder().decodeFromBytes(PDUtil.hexToBytes(await sl.get<Vault>().getPrivateKey())));
    // Construct execute request
    ExecuteOperationsRequest request = ExecuteOperationsRequest(
      rawOperations: PDUtil.byteToHex(RawOperationCoder.encodeToBytes(op))
    );
    // Make request
    RPCResponse resp = await this.rpcClient.makeRpcRequest(request);
    if (resp.isError) {
      return resp;
    }
    OperationsResponse opResp = resp;
    if (opResp.operations[0].valid) {
      this.account.balance-=Currency(amount);
      this.account.nOperation++;
      this.getAccountOperations();
    }
    return resp;
  }
}