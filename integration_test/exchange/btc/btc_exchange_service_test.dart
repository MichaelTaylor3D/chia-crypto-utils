// ignore_for_file: lines_longer_than_80_chars
@Timeout(Duration(minutes: 1))

import 'dart:async';

import 'package:chia_crypto_utils/chia_crypto_utils.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

Future<void> main() async {
  if (!(await SimulatorUtils.checkIfSimulatorIsRunning())) {
    print(SimulatorUtils.simulatorNotRunningWarning);
    return;
  }

  final simulatorHttpRpc = SimulatorHttpRpc(
    SimulatorUtils.simulatorUrl,
    certBytes: SimulatorUtils.certBytes,
    keyBytes: SimulatorUtils.keyBytes,
  );

  final fullNodeSimulator = SimulatorFullNodeInterface(simulatorHttpRpc);

  ChiaNetworkContextWrapper().registerNetworkContext(Network.mainnet);
  final walletService = StandardWalletService();
  final exchangeService = BtcExchangeService();
  final btcToXchService = BtcToXchService();
  final xchToBtcService = XchToBtcService();

  test(
      'should transfer XCH to escrow address and fail to claw back funds to XCH holder before delay has passed',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final xchHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const btcHolderSignedPublicKey =
        'ac72743c39137845af0991c71796206c7784b49b76fa30f216ccdeba84e23b28b81d5af48a6cc754d6438057c084f206_b60876a2f323721d8404935991b2c2e392af7e07d93aeb68317646a4c72b7392c00c88331e1ca90330cc9511cd6f2a510b55ee0918ed4d1d58dbf06c805044b9dc906a58ed5252e9dd95d22ccdc9f3016e1848d95f998a2bfbe6f74f5040f688';
    final btcHolderPublicKey = exchangeService.parseSignedPublicKey(btcHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // user inputs how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = XchToBtcService.generateEscrowPuzzlehash(
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive coins in clawback case
    final clawbackPuzzlehash = xchHolder.firstPuzzlehash;

    // the clawback spend bundle will fail if pushed before the clawback delay period passes
    final clawbackSpendBundle = xchToBtcService.createClawbackSpendBundle(
      payments: [Payment(escrowCoins.totalValue, clawbackPuzzlehash)],
      coinsInput: escrowCoins,
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    expect(
      () async {
        await fullNodeSimulator.pushTransaction(clawbackSpendBundle);
      },
      throwsException,
    );
  });

  test(
      'should transfer XCH to escrow address and claw back funds to XCH holder after delay has passed',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final xchHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const btcHolderSignedPublicKey =
        'ac72743c39137845af0991c71796206c7784b49b76fa30f216ccdeba84e23b28b81d5af48a6cc754d6438057c084f206_b60876a2f323721d8404935991b2c2e392af7e07d93aeb68317646a4c72b7392c00c88331e1ca90330cc9511cd6f2a510b55ee0918ed4d1d58dbf06c805044b9dc906a58ed5252e9dd95d22ccdc9f3016e1848d95f998a2bfbe6f74f5040f688';
    final btcHolderPublicKey = exchangeService.parseSignedPublicKey(btcHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // shorten delay for testing purposes
    const clawbackDelaySeconds = 5;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = XchToBtcService.generateEscrowPuzzlehash(
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive coins in clawback case
    final clawbackPuzzlehash = xchHolder.firstPuzzlehash;

    final startingClawbackAddressBalance = await fullNodeSimulator.getBalance([clawbackPuzzlehash]);

    // the clawback spend bundle can be pushed after the clawback delay has passed in order to reclaim funds
    // in the event that the other party doesn't pay the lightning invoice within that time
    final clawbackSpendBundle = xchToBtcService.createClawbackSpendBundle(
      payments: [Payment(escrowCoins.totalValue, clawbackPuzzlehash)],
      coinsInput: escrowCoins,
      clawbackDelaySeconds: clawbackDelaySeconds,
      requestorPrivateKey: xchHolderPrivateKey,
      sweepPaymentHash: sweepPaymentHash,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    // the earliest you can spend a time-locked coin is 2 blocks later, since the time is checked
    // against the timestamp of the previous block
    for (var i = 0; i < 2; i++) {
      await fullNodeSimulator.moveToNextBlock();
    }

    // wait until clawback delay period has passed
    await Future<void>.delayed(const Duration(seconds: 10), () async {
      await fullNodeSimulator.pushTransaction(clawbackSpendBundle);
      await fullNodeSimulator.moveToNextBlock();
      final endingClawbackAddressBalance = await fullNodeSimulator.getBalance([clawbackPuzzlehash]);

      expect(
        endingClawbackAddressBalance,
        equals(startingClawbackAddressBalance + escrowCoins.totalValue),
      );
    });
  });

  test(
      'should transfer XCH to escrow address and claw back funds to XCH holder early using private key before delay has passed',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final xchHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const btcHolderSignedPublicKey =
        'a83e5abe134e3d871f48bbbab7e0bd571700ca4a50694573dd301158f3458bdeb5d1e8c742558448f4d247118a21d4a5_a81d9d56a3514821c80a012819456b7eda8a9db4558a26811570ccff723deeb0dc4c2866f53455141b4853b80b515d4707726b8dbbb68cd9b478e0e93675e183cef0e03e97401f1ab02f9eea38d4caccdcf9b43ac0486a7d4792a35be6890b18';
    final btcHolderPublicKey = exchangeService.parseSignedPublicKey(btcHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // user inputs how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = XchToBtcService.generateEscrowPuzzlehash(
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive coins in clawback case
    final clawbackPuzzlehash = xchHolder.firstPuzzlehash;

    final startingClawbackAddressBalance = await fullNodeSimulator.getBalance([clawbackPuzzlehash]);

    // in the event that something goes wrong with the exchange or the two parties mutually decide to
    // abort the exchange, the XCH holder may receive funds back before the clawback delay passes
    // if the BTC holder provides them with their private key
    final btcHolderPrivateKey =
        PrivateKey.fromHex('308f34305ed545c7b6bdefe9fff88176dc3b1a68c40f9065e2cf24c98bf6a4e1');

    final clawbackSpendBundle = xchToBtcService.createClawbackSpendBundleWithPk(
      payments: [Payment(escrowCoins.totalValue, clawbackPuzzlehash)],
      coinsInput: escrowCoins,
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash,
      fulfillerPrivateKey: btcHolderPrivateKey,
    );

    await fullNodeSimulator.pushTransaction(clawbackSpendBundle);
    await fullNodeSimulator.moveToNextBlock();
    final endingClawbackAddressBalance = await fullNodeSimulator.getBalance([clawbackPuzzlehash]);

    expect(
      endingClawbackAddressBalance,
      equals(startingClawbackAddressBalance + escrowCoins.totalValue),
    );
  });

  test(
      'should transfer XCH to escrow address and fail claw back funds to XCH holder early using wrong private key',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final xchHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const btcHolderSignedPublicKey =
        'a83e5abe134e3d871f48bbbab7e0bd571700ca4a50694573dd301158f3458bdeb5d1e8c742558448f4d247118a21d4a5_a81d9d56a3514821c80a012819456b7eda8a9db4558a26811570ccff723deeb0dc4c2866f53455141b4853b80b515d4707726b8dbbb68cd9b478e0e93675e183cef0e03e97401f1ab02f9eea38d4caccdcf9b43ac0486a7d4792a35be6890b18';
    final btcHolderPublicKey = exchangeService.parseSignedPublicKey(btcHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // user inputs how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = XchToBtcService.generateEscrowPuzzlehash(
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive coins in clawback case
    final clawbackPuzzlehash = xchHolder.firstPuzzlehash;

    // the XCH holder inputs an incorrect private key
    final incorrectPrivateKey = PrivateKey.generate();

    expect(
      () async {
        final sweepSpendBundle = btcToXchService.createSweepSpendBundleWithPk(
          payments: [Payment(escrowCoins.totalValue, clawbackPuzzlehash)],
          coinsInput: escrowCoins,
          requestorPrivateKey: xchHolderPrivateKey,
          clawbackDelaySeconds: clawbackDelaySeconds,
          sweepPaymentHash: sweepPaymentHash,
          fulfillerPrivateKey: incorrectPrivateKey,
        );

        await fullNodeSimulator.pushTransaction(sweepSpendBundle);
      },
      throwsException,
    );
  });

  test('should transfer XCH to escrow address and sweep funds to BTC holder using preimage',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    final btcHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final btcHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const xchHolderSignedPublicKey =
        'ad6abe3d432ccce5b40995611c4db6d71e2678f142b8635940c32c4b1c35dde7b01ab42581075eaee173aba747373f71_97c0d2c1acea7708df1eb4a75f625ca1fe95a9aa141a86c2e18bdfd1e8716cba2888f6230ea122ce9478a78f8257beaf0dfb81714f4de6337fa671cc29bb2d4e18e9aae31829016fd94f14e99f86a9ad990f2740d02583c6a85dc4b6b0233aaa';
    final xchHolderPublicKey = exchangeService.parseSignedPublicKey(xchHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // user inputs how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = BtcToXchService.generateEscrowPuzzlehash(
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: xchHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive funds
    final sweepPuzzlehash = btcHolder.firstPuzzlehash;
    final startingSweepAddressBalance = await fullNodeSimulator.getBalance([sweepPuzzlehash]);

    // the BTC holder inputs the lightning preimage receipt they receive upon payment of the
    // lightning invoice to sweep funds
    // the payment hash is the hash of the preimage
    final sweepPreimage =
        '5c1f10653dc3ff0531b77351dc6676de2e1f5f53c9f0a8867bcb054648f46a32'.hexToBytes();

    final sweepSpendBundle = btcToXchService.createSweepSpendBundle(
      payments: [Payment(escrowCoins.totalValue, sweepPuzzlehash)],
      coinsInput: escrowCoins,
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash,
      sweepPreimage: sweepPreimage,
      fulfillerPublicKey: xchHolderPublicKey,
    );

    await fullNodeSimulator.pushTransaction(sweepSpendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final endingSweepAddressBalance = await fullNodeSimulator.getBalance([sweepPuzzlehash]);

    expect(
      endingSweepAddressBalance,
      equals(startingSweepAddressBalance + escrowCoins.totalValue),
    );
  });

  test(
      'should transfer XCH to escrow address and fail to sweep funds to BTC holder when preimage is incorrect',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    final btcHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final btcHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const xchHolderSignedPublicKey =
        'ad6abe3d432ccce5b40995611c4db6d71e2678f142b8635940c32c4b1c35dde7b01ab42581075eaee173aba747373f71_97c0d2c1acea7708df1eb4a75f625ca1fe95a9aa141a86c2e18bdfd1e8716cba2888f6230ea122ce9478a78f8257beaf0dfb81714f4de6337fa671cc29bb2d4e18e9aae31829016fd94f14e99f86a9ad990f2740d02583c6a85dc4b6b0233aaa';
    final xchHolderPublicKey = exchangeService.parseSignedPublicKey(xchHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // user inputs how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = BtcToXchService.generateEscrowPuzzlehash(
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: xchHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive funds
    final sweepPuzzlehash = btcHolder.firstPuzzlehash;

    // the BTC holder inputs an incorrect lightning preimage
    final incorrectPreimage = Puzzlehash.zeros().toBytes();

    expect(
      () {
        btcToXchService.createSweepSpendBundle(
          payments: [Payment(escrowCoins.totalValue, sweepPuzzlehash)],
          coinsInput: escrowCoins,
          requestorPrivateKey: btcHolderPrivateKey,
          clawbackDelaySeconds: clawbackDelaySeconds,
          sweepPaymentHash: sweepPaymentHash,
          sweepPreimage: incorrectPreimage,
          fulfillerPublicKey: xchHolderPublicKey,
        );
      },
      throwsStateError,
    );
  });

  test('should transfer XCH to escrow address and sweep funds to BTC holder using private key',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    final btcHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final btcHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const xchHolderSignedPublicKey =
        'a83e5abe134e3d871f48bbbab7e0bd571700ca4a50694573dd301158f3458bdeb5d1e8c742558448f4d247118a21d4a5_a81d9d56a3514821c80a012819456b7eda8a9db4558a26811570ccff723deeb0dc4c2866f53455141b4853b80b515d4707726b8dbbb68cd9b478e0e93675e183cef0e03e97401f1ab02f9eea38d4caccdcf9b43ac0486a7d4792a35be6890b18';
    final xchHolderPublicKey = exchangeService.parseSignedPublicKey(xchHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // user inputs how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = BtcToXchService.generateEscrowPuzzlehash(
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: xchHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive funds
    final sweepPuzzlehash = btcHolder.firstPuzzlehash;
    final startingSweepAddressBalance = await fullNodeSimulator.getBalance([sweepPuzzlehash]);

    // after the lightning invoice is paid, the XCH holder may share their disposable private key
    // the BTC holder inputs the private key, allowing them to sweep funds from the escrow address
    final xchHolderPrivateKey =
        PrivateKey.fromHex('308f34305ed545c7b6bdefe9fff88176dc3b1a68c40f9065e2cf24c98bf6a4e1');

    final sweepSpendBundle = btcToXchService.createSweepSpendBundleWithPk(
      payments: [Payment(escrowCoins.totalValue, sweepPuzzlehash)],
      coinsInput: escrowCoins,
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash,
      fulfillerPrivateKey: xchHolderPrivateKey,
    );

    await fullNodeSimulator.pushTransaction(sweepSpendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final endingSweepAddressBalance = await fullNodeSimulator.getBalance([sweepPuzzlehash]);

    expect(
      endingSweepAddressBalance,
      equals(startingSweepAddressBalance + escrowCoins.totalValue),
    );
  });

  test(
      'should transfer XCH to escrow address and fail to sweep funds to BTC holder when private key is incorrect',
      () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    final btcHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // generate disposable private key for user
    final btcHolderPrivateKey = PrivateKey.generate();

    // user inputs signed public key of counter party, which is parsed and validated to ensure that
    // it was generated by our exchange service
    const xchHolderSignedPublicKey =
        'ad6abe3d432ccce5b40995611c4db6d71e2678f142b8635940c32c4b1c35dde7b01ab42581075eaee173aba747373f71_97c0d2c1acea7708df1eb4a75f625ca1fe95a9aa141a86c2e18bdfd1e8716cba2888f6230ea122ce9478a78f8257beaf0dfb81714f4de6337fa671cc29bb2d4e18e9aae31829016fd94f14e99f86a9ad990f2740d02583c6a85dc4b6b0233aaa';
    final xchHolderPublicKey = exchangeService.parseSignedPublicKey(xchHolderSignedPublicKey);

    // user inputs lightning payment request, which is decoded to get the payment hash
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // user inputs how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // generate address for XCH holder to send funds to
    final escrowPuzzlehash = BtcToXchService.generateEscrowPuzzlehash(
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: xchHolderPublicKey,
    );

    // XCH holder transfers funds to escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, escrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final escrowCoins = await fullNodeSimulator.getCoinsByPuzzleHashes([escrowPuzzlehash]);

    // user specifies where they want to receive funds
    final sweepPuzzlehash = btcHolder.firstPuzzlehash;

    // the BTC holder inputs an incorrect private key
    final incorrectPrivateKey = PrivateKey.generate();

    expect(
      () async {
        final sweepSpendBundle = btcToXchService.createSweepSpendBundleWithPk(
          payments: [Payment(escrowCoins.totalValue, sweepPuzzlehash)],
          coinsInput: escrowCoins,
          requestorPrivateKey: btcHolderPrivateKey,
          clawbackDelaySeconds: clawbackDelaySeconds,
          sweepPaymentHash: sweepPaymentHash,
          fulfillerPrivateKey: incorrectPrivateKey,
        );

        await fullNodeSimulator.pushTransaction(sweepSpendBundle);
      },
      throwsException,
    );
  });

  test('exchange should fail if parties input different timeouts', () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // disposable private keys are generated for each user
    final btcHolderPrivateKey = PrivateKey.generate();
    final btcHolderPublicKey = btcHolderPrivateKey.getG1();

    final xchHolderPrivateKey = PrivateKey.generate();
    final xchHolderPublicKey = xchHolderPrivateKey.getG1();

    // XCH holder creates a lightning payment request, which both users paste into the program
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // escrow address is generated on BTC holder's side
    final btcHolderescrowPuzzlehash = BtcToXchService.generateEscrowPuzzlehash(
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: 60,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: xchHolderPublicKey,
    );

    // escrow address is generated on XCH holder's side, but they input a different clawback delay
    final xchHolderescrowPuzzlehash = XchToBtcService.generateEscrowPuzzlehash(
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: 40,
      sweepPaymentHash: sweepPaymentHash,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    // exchange puzzlehashes do not match
    expect(btcHolderescrowPuzzlehash, isNot(xchHolderescrowPuzzlehash));

    // XCH holder sends funds to their version of the escrow address, but they aren't available at the
    // BTC holder's version escrow address
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, xchHolderescrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final xchHolderescrowCoins =
        await fullNodeSimulator.getCoinsByPuzzleHashes([xchHolderescrowPuzzlehash]);
    final btcHolderescrowCoins =
        await fullNodeSimulator.getCoinsByPuzzleHashes([btcHolderescrowPuzzlehash]);

    expect(xchHolderescrowCoins.totalValue, equals(xchHolderCoins.totalValue));
    expect(btcHolderescrowCoins, isEmpty);
  });

  test('exchange should fail if user shares wrong signed public key', () async {
    final xchHolder = ChiaEnthusiast(fullNodeSimulator, walletSize: 2);
    await xchHolder.farmCoins();
    await xchHolder.refreshCoins();

    // disposable private keys are generated for each user
    final btcHolderPrivateKey = PrivateKey.generate();
    final btcHolderPublicKey = btcHolderPrivateKey.getG1();

    final xchHolderPrivateKey = PrivateKey.generate();

    // XCH holder accidentally shares the wrong signed public key
    // although it has the correct format, it was signed by the wrong private key
    final xchHolderWrongPrivateKey =
        PrivateKey.fromHex('308f34305ed545c7b6bdefe9fff88176dc3b1a68c40f9065e2cf24c98bf6a4e1');
    final xchHolderWrongSignedPublicKey =
        exchangeService.createSignedPublicKey(xchHolderWrongPrivateKey);

    // BTC holder inputs the wrong signed public key that the XCH holder shared with them, which
    // is validated and parsed by the program because it has the correct format
    final xchHolderWrongPublicKey =
        exchangeService.parseSignedPublicKey(xchHolderWrongSignedPublicKey);

    // XCH holder creates a lightning payment request, which both users paste into the program
    const paymentRequest =
        'lnbc1u1p3huyzkpp5vw6fkrw9lr3pvved40zpp4jway4g4ee6uzsaj208dxqxgm2rtkvqdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdrxkxglt5qydruqqqqryqqqqthqqpyrzjqw8c7yfutqqy3kz8662fxutjvef7q2ujsxtt45csu0k688lkzu3ldrxkxglt5qydruqqqqryqqqqthqqpysp5jzgpj4990chtj9f9g2f6mhvgtzajzckx774yuh0klnr3hmvrqtjq9qypqsqkrvl3sqd4q4dm9axttfa6frg7gffguq3rzuvvm2fpuqsgg90l4nz8zgc3wx7gggm04xtwq59vftm25emwp9mtvmvjg756dyzn2dm98qpakw4u8';
    final decodedPaymentRequest = decodeLightningPaymentRequest(paymentRequest);
    final sweepPaymentHash = decodedPaymentRequest.tags.paymentHash;

    // users input how long to allow for exchange before funds can be clawed back
    const clawbackDelaySeconds = 3600;

    // escrow address is generated on BTC holder's side
    final btcHolderescrowPuzzlehash = BtcToXchService.generateEscrowPuzzlehash(
      requestorPrivateKey: btcHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash!,
      fulfillerPublicKey: xchHolderWrongPublicKey,
    );

    // escrow address is generated on XCH holder's side
    final xchHolderescrowPuzzlehash = XchToBtcService.generateEscrowPuzzlehash(
      requestorPrivateKey: xchHolderPrivateKey,
      clawbackDelaySeconds: clawbackDelaySeconds,
      sweepPaymentHash: sweepPaymentHash,
      fulfillerPublicKey: btcHolderPublicKey,
    );

    // exchange puzzlehashes do not match
    expect(btcHolderescrowPuzzlehash, isNot(xchHolderescrowPuzzlehash));

    // XCH holder sends funds to their version of the escrow address, but they aren't available at the
    // BTC holder's version escrow address and the BTC holder cannot sweep the funds
    final xchHolderCoins = xchHolder.standardCoins;

    final spendBundle = walletService.createSpendBundle(
      payments: [Payment(xchHolderCoins.totalValue, xchHolderescrowPuzzlehash)],
      coinsInput: xchHolderCoins,
      changePuzzlehash: xchHolder.firstPuzzlehash,
      keychain: xchHolder.keychain,
    );
    await fullNodeSimulator.pushTransaction(spendBundle);
    await fullNodeSimulator.moveToNextBlock();

    final xchHolderescrowCoins =
        await fullNodeSimulator.getCoinsByPuzzleHashes([xchHolderescrowPuzzlehash]);
    final btcHolderescrowCoins =
        await fullNodeSimulator.getCoinsByPuzzleHashes([btcHolderescrowPuzzlehash]);

    expect(xchHolderescrowCoins.totalValue, equals(xchHolderCoins.totalValue));
    expect(btcHolderescrowCoins, isEmpty);
  });
}