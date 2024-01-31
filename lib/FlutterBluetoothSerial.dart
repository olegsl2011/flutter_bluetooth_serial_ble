part of flutter_bluetooth_serial_ble;

class FlutterBluetoothSerial {
  // Plugin
  static const String namespace = 'flutter_bluetooth_serial_ble';

  static FlutterBluetoothSerial _instance = new FlutterBluetoothSerial._();

  static FlutterBluetoothSerial get instance => _instance;

  static final MethodChannel _methodChannel =
      const MethodChannel('$namespace/methods');

  FlutterBluetoothSerial._() {
    _methodChannel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'handlePairingRequest':
          if (_pairingRequestHandler != null) {
            return _pairingRequestHandler!(
                BluetoothPairingRequest.fromMap(call.arguments));
          }
          break;

        default:
          throw 'unknown common code method - not implemented';
      }
    });
  }

  /* Status */
  /// Checks is the Bluetooth interface avaliable on host device.
  /// In the process of supporting multiple platforms, now calls isEnabled.
  @Deprecated('Use `isEnabled` instead')
  Future<bool?> get isAvailable async => isEnabled; //THINK It's a little questionable to merge this
      // await _methodChannel.invokeMethod('isAvailable');

  /// Describes is the Bluetooth interface enabled on host device.
  Future<bool?> get isEnabled async { //RAINY The state methods suffered a little in the transition to QuickBlue.
    try {
      final e = await QuickBlue.isBluetoothAvailable();
      if (e) {
        _lastState = BluetoothState.STATE_ON;
      } else {
        _lastState = BluetoothState.UNKNOWN; //THINK Not sure.
      }
      return e;
    } catch (e, s) {
      _lastState = BluetoothState.ERROR; //THINK Not sure.
      rethrow;
    }
  }
    // await _methodChannel.invokeMethod('isEnabled');

  /// Checks is the Bluetooth interface enabled on host device.
  @Deprecated('Use `isEnabled` instead')
  Future<bool?> get isOn async => isEnabled;

  // static final EventChannel _stateChannel =
  //     const EventChannel('$namespace/state');

  BluetoothState _lastState = BluetoothState.UNKNOWN;

  /// Allows monitoring the Bluetooth adapter state changes.
  Stream<BluetoothState> onStateChanged() => QuickBlue.availabilityChangeStream
      .asBroadcastStream()
      .map((event) {
    //CHECK I'm not sure about this.  I suspect possible discrepancies between QuickBlue and this - for instance, maybe QuickBlue doesn't report classic BT.
    //CHECK Actually, I'm not even sure the BLE states are real - they don't show up in the Android documentation....
    //   Yeah, actually, I'm going to use e.g. STATE_ON instead of STATE_BLE_ON
    switch (event) {
      case AvailabilityState.unknown: return _lastState = BluetoothState.UNKNOWN;
      case AvailabilityState.resetting: return _lastState = BluetoothState.STATE_TURNING_ON; //THINK Not sure about this conversion.
      case AvailabilityState.unsupported: return _lastState = BluetoothState.ERROR;
      case AvailabilityState.unauthorized: return _lastState = BluetoothState.ERROR;
      case AvailabilityState.poweredOff: return _lastState = BluetoothState.STATE_OFF;
      case AvailabilityState.poweredOn: return _lastState = BluetoothState.STATE_ON; //THINK ...Why are there separate states for ON and BLE_ON?  This is trepidatious.
      default: return _lastState = BluetoothState.ERROR;
    }
  });

  /// State of the Bluetooth adapter.
  /// Returns the last
  Future<BluetoothState> get state async => _lastState;
  // BluetoothState.fromUnderlyingValue(await _methodChannel.invokeMethod('getState'));

  /// Returns the hardware address of the local Bluetooth adapter.
  /// (Only available on Android.)
  ///
  /// Does not work for third party applications starting at Android 6.0.
  Future<String?> get address => _methodChannel.invokeMethod("getAddress"); //CHECK This isn't available through QuickBlue; I guess I'mma just leave it...?

  /// Returns the friendly Bluetooth name of the local Bluetooth adapter.
  /// (Only available on Android.)
  ///
  /// This name is visible to remote Bluetooth devices.
  ///
  /// Does not work for third party applications starting at Android 6.0.
  Future<String?> get name => _methodChannel.invokeMethod("getName"); //DITTO

  /// Sets the friendly Bluetooth name of the local Bluetooth adapter.
  /// (Only available on Android.)
  ///
  /// This name is visible to remote Bluetooth devices.
  ///
  /// Valid Bluetooth names are a maximum of 248 bytes using UTF-8 encoding,
  /// although many remote devices can only display the first 40 characters,
  /// and some may be limited to just 20.
  ///
  /// Does not work for third party applications starting at Android 6.0.
  Future<bool?> changeName(String name) =>
      _methodChannel.invokeMethod("setName", {"name": name}); //DITTO

  /* Adapter settings and general */
  /// Tries to enable Bluetooth interface (if disabled).
  /// Probably results in asking user for confirmation.
  /// (Only available on Android.)
  Future<bool?> requestEnable() async =>
      await _methodChannel.invokeMethod('requestEnable'); //DITTO

  /// Tries to disable Bluetooth interface (if enabled).
  /// (Only available on Android.)
  Future<bool?> requestDisable() async =>
      await _methodChannel.invokeMethod('requestDisable'); //DITTO

  /// Opens the Bluetooth platform system settings.
  /// (Only available on Android.)
  Future<void> openSettings() async =>
      await _methodChannel.invokeMethod('openSettings'); //DITTO

  /* Discovering and bonding devices */
  /// Checks bond state for given address (might be from system cache).
  /// (Only available on Android.)
  Future<BluetoothBondState> getBondStateForAddress(String address) async { //DITTO
    return BluetoothBondState.fromUnderlyingValue(await _methodChannel
        .invokeMethod('getDeviceBondState', {"address": address}));
  }

  /// Starts outgoing bonding (pairing) with device with given address.
  /// Returns true if bonded, false if canceled or failed gracefully.
  /// (Only available on Android.)
  ///
  /// `pin` or `passkeyConfirm` could be used to automate the bonding process,
  /// using provided pin or confirmation if necessary. Can be used only if no
  /// pairing request handler is already registered.
  ///
  /// Note: `passkeyConfirm` will probably not work, since 3rd party apps cannot
  /// get `BLUETOOTH_PRIVILEGED` permission (at least on newest Androids).
  Future<bool?> bondDeviceAtAddress(String address,
      {String? pin, bool? passkeyConfirm}) async { //DITTO
    if (pin != null || passkeyConfirm != null) {
      if (_pairingRequestHandler != null) {
        throw "pairing request handler already registered";
      }
      setPairingRequestHandler((BluetoothPairingRequest request) async {
        Future.delayed(Duration(seconds: 1), () {
          setPairingRequestHandler(null);
        });
        if (pin != null) {
          switch (request.pairingVariant) {
            case PairingVariant.Pin:
              return pin;
            default:
              // Other pairing variant requested, ignoring pin
              break;
          }
        }
        if (passkeyConfirm != null) {
          switch (request.pairingVariant) {
            case PairingVariant.Consent:
            case PairingVariant.PasskeyConfirmation:
              return passkeyConfirm;
            default:
              // Other pairing variant requested, ignoring confirming
              break;
          }
        }
        // Other pairing variant used, cannot automate
        return null;
      });
    }
    return await _methodChannel
        .invokeMethod('bondDevice', {"address": address});
  }

  /// Removes bond with device with specified address.
  /// Returns true if unbonded, false if canceled or failed gracefully.
  /// (Only available on Android.)
  ///
  /// Note: May not work at every Android device!
  Future<bool?> removeDeviceBondWithAddress(String address) async => //DITTO
      await _methodChannel
          .invokeMethod('removeDeviceBond', {'address': address});

  // Function used as pairing request handler.
  Function? _pairingRequestHandler;

  /// Allows listening and responsing for incoming pairing requests.
  /// (Only available on Android.)
  ///
  /// Various variants of pairing requests might require different returns:
  /// * `PairingVariant.Pin` or `PairingVariant.Pin16Digits`
  /// (prompt to enter a pin)
  ///   - return string containing the pin for pairing
  ///   - return `false` to reject.
  /// * `BluetoothDevice.PasskeyConfirmation`
  /// (user needs to confirm displayed passkey, no rewriting necessary)
  ///   - return `true` to accept, `false` to reject.
  ///   - there is `passkey` parameter available.
  /// * `PairingVariant.Consent`
  /// (just prompt with device name to accept without any code or passkey)
  ///   - return `true` to accept, `false` to reject.
  ///
  /// If returned null, the request will be passed for manual pairing
  /// using default Android Bluetooth settings pairing dialog.
  ///
  /// Note: Accepting request variant of `PasskeyConfirmation` and `Consent`
  /// will probably fail, because it require Android `setPairingConfirmation`
  /// which requires `BLUETOOTH_PRIVILEGED` permission that 3rd party apps
  /// cannot acquire (at least on newest Androids) due to security reasons.
  ///
  /// Note: It is necessary to return from handler within 10 seconds, since
  /// Android BroadcastReceiver can wait safely only up to that duration.
  void setPairingRequestHandler(
      Future<dynamic> handler(BluetoothPairingRequest request)?) { //DITTO
    if (handler == null) {
      _pairingRequestHandler = null;
      _methodChannel.invokeMethod('pairingRequestHandlingDisable');
      return;
    }
    if (_pairingRequestHandler == null) {
      _methodChannel.invokeMethod('pairingRequestHandlingEnable');
    }
    _pairingRequestHandler = handler;
  }

  /// Returns list of bonded devices.
  /// (Only available on Android.)
  Future<List<BluetoothDevice>> getBondedDevices() async { //DITTO
    final List list = await (_methodChannel.invokeMethod('getBondedDevices'));
    return list.map((map) => BluetoothDevice.fromMap(map)).toList();
  }

  // static final EventChannel _discoveryChannel =
  // const EventChannel('$namespace/discovery');

  /// Describes is the dicovery process of Bluetooth devices running.
  Future<bool?> get isDiscovering async => BluetoothCallbackTracker.INSTANCE.isScanning(); // Doesn't strictly check if scanning; only if BluetoothCallbackTracker still has outstanding scan requests.
  // await _methodChannel.invokeMethod('isDiscovering');

  Token? _scanToken;

  /// Starts discovery and provides stream of `BluetoothDiscoveryResult`s.
  Stream<BluetoothDiscoveryResult> startDiscovery() async* {
    //RAINY We mix calls to BluetoothCallbackTracker and QuickBlue, in this class.  If e.g. BCT ever pulls in a different bt lib, that may come back to bite us.
    var s = BluetoothCallbackTracker.INSTANCE.subscribeForScanResults().map((event) {
      Map<dynamic, dynamic> discoveryResult = {};
      discoveryResult["address"] = event.deviceId;
      discoveryResult["name"] = event.name;
      // discoveryResult["type"] = "UNKNOWN"; //DUMMY Not given; what even is type?
    //discoveryResult["class"] = deviceClass; // @TODO . it isn't my priority for now !BluetoothClass!
      discoveryResult["isConnected"] = false; //DUMMY I could probably stitch this info together....
      // discoveryResult["bondState"] = "UNKNOWN";
      discoveryResult["rssi"] = event.rssi;
      return BluetoothDiscoveryResult.fromMap(discoveryResult);
    });
    _scanToken = await BluetoothCallbackTracker.INSTANCE.startScan();
    yield* s;
    // late StreamSubscription subscription;
    // StreamController controller;
    //
    // controller = new StreamController(
    //   onCancel: () {
    //     // `cancelDiscovery` happens automaticly by platform code when closing event sink
    //     subscription.cancel();
    //   },
    // );
    //
    // await _methodChannel.invokeMethod('startDiscovery');
    //
    // subscription = _discoveryChannel.receiveBroadcastStream().listen(
    //   controller.add,
    //   onError: controller.addError,
    //   onDone: controller.close,
    // );
    //
    // yield* controller.stream
    //     .map((map) => BluetoothDiscoveryResult.fromMap(map));
  }

  /// Cancels the discovery
  Future<void> cancelDiscovery() async {
    if (_scanToken != null) {
      return BluetoothCallbackTracker.INSTANCE.stopScan(_scanToken!);
    }
  }
      // await _methodChannel.invokeMethod('cancelDiscovery');

  /// Describes is the local device in discoverable mode.
  /// (Only available on Android.)
  Future<bool?> get isDiscoverable =>
      _methodChannel.invokeMethod("isDiscoverable"); //DITTO

  /// Asks for discoverable mode (probably always prompt for user interaction in fact).
  /// Returns number of seconds acquired or zero if canceled or failed gracefully.
  /// (Only available on Android.)
  ///
  /// Duration might be capped to 120, 300 or 3600 seconds on some devices.
  Future<int?> requestDiscoverable(int durationInSeconds) async =>
      await _methodChannel
          .invokeMethod("requestDiscoverable", {"duration": durationInSeconds});

  /* Connecting and connection */
  // Default connection methods
  BluetoothConnection? _defaultConnection;

  @Deprecated('Use `BluetoothConnection.isEnabled` instead')
  Future<bool> get isConnected async => Future.value(
      _defaultConnection == null ? false : _defaultConnection!.isConnected);

  @Deprecated('Use `BluetoothConnection.toAddress(device.address)` instead')
  Future<void> connect(BluetoothDevice device) =>
      connectToAddress(device.address);

  @Deprecated('Use `BluetoothConnection.toAddress(address)` instead')
  Future<void> connectToAddress(String? address, {ConnectionType type = ConnectionType.AUTO}) => Future(() async {
        _defaultConnection = await BluetoothConnection.toAddress(address, type: type);
      });

  @Deprecated(
      'Use `BluetoothConnection.finish` or `BluetoothConnection.close` instead')
  Future<void> disconnect() => _defaultConnection!.finish();

  @Deprecated('Use `BluetoothConnection.input` instead')
  Stream<Uint8List>? onRead() => _defaultConnection!.input;

  @Deprecated(
      'Use `BluetoothConnection.output` with some decoding (such as `ascii.decode` for strings) instead')
  Future<void> write(String message) {
    _defaultConnection!.output.add(utf8.encode(message) as Uint8List);
    return _defaultConnection!.output.allSent;
  }

  @Deprecated('Use `BluetoothConnection.output` instead')
  Future<void> writeBytes(Uint8List message) {
    _defaultConnection!.output.add(message);
    return _defaultConnection!.output.allSent;
  }
}
