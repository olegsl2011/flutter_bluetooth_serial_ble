part of flutter_bluetooth_serial_ble;

//DUMMY I powered off the device, but it did not register disconnect, even when I wrote more data
//THINK So, one of my assumptions was that stream errors close the stream.  This apparently isn't necessarily true, and so some of this code may have related bugs in it.
//RAINY This could probably be significantly simplified - factor out the extraneous Listener class, remove some of the unused legacy methods, etc.

class BleBluetoothConnection implements SerialListener, BluetoothConnection {
  bool _manuallyDisconnected = false;
  final String address;

  final _connectedStreamController = StreamController<bool>();
  late final connectedStream = _connectedStreamController.stream.asBroadcastStream();

  BleBluetoothConnection(this.address) {
    log("-->BBC init");
    _readStreamController = StreamController<Uint8List>();
    input = _readStreamController.stream;
    _writeStreamController.delegate.stream.listen((data) async {
      log("-->BBC.writeSC");
      await write(data);
      log("<--BBC.writeSC");
    });

    // Start the connected stream broadcasting
    connectedStream.listen((c) {});

    _stuffToCancel.add(BluetoothCallbackTracker.INSTANCE.subscribeForConnectionResults(address).listen((event) async {
      log("-->BCT.connectionResult $event");
      await _onConnectionStateChange(address, event);
      log("<--BCT.connectionResult");
    }));

    BluetoothCallbackTracker.INSTANCE.connect(address);
    //MISC There was a disconnectBroadcastReceiver, maybe background disconnects aren't registered on some platforms (Android)?

    _listener = this;
    log("<--BBC init");
  }


  //// BluetoothConnection, mostly copied

  // These things were for communicating with platform code, which is here replaced with QuickBlue/BluetoothCallbackTracker
  final int? _id = null;
  StreamSubscription<Uint8List> get _readStreamSubscription => throw UnimplementedError();
  set _readStreamSubscription(StreamSubscription<Uint8List> value) => throw UnimplementedError();
  EventChannel get _readChannel => throw UnimplementedError();

  late StreamController<Uint8List> _readStreamController;

  @override
  late final Stream<Uint8List>? input;

  final _writeStreamController = BleBluetoothStreamSink<Uint8List>();

  @override
  late BluetoothStreamSink<Uint8List> output = _writeStreamController;

  @override
  bool get isConnected => _connected && output.isConnected; //CHECK Did the && resolve the conflict?

  /// Should be called to make sure the connection is closed and resources are freed (sockets/channels).
  void dispose() {
    log("-->BBC.dispose");
    finish();
    log("<--BBC.dispose");
  }

  /// Closes connection (rather immediately), in result should also disconnect.
  @override
  Future<void> close() async {
    log("-->BBC.close");
    await disconnect();
    await Future.wait([
      output.close(), //CHECK When this threw, the app subsequently couldn't discover devices; find out why.  ...It ALSO won't discover more devices under any other circumstance, soooo....
      (!_readStreamController.isClosed)
          ? _readStreamController.close()
          : Future.value(/* Empty future */)
    ], eagerError: true);
    log("<--BBC.close");
  }

  /// Closes connection (rather immediately), in result should also disconnect.
  @Deprecated('Use `close` instead')
  Future<void> cancel() => this.close();

  /// Closes connection (rather gracefully), in result should also disconnect.
  Future<void> finish() async {
    log("-->BBC.finish");
    await output.allSent;
    await close();
    log("<--BBC.close");
  }



  //// SerialListener

  //THINK Maybe these should just be folded back into their callers

  @override
  void onSerialConnect() {
    log("-->BBC.onSerialConnect");
    output.isConnected = true;
    log("<--BBC.onSerialConnect");
  }

  @override
  void onSerialConnectError(Exception e) {
    log("-->BBC.onSerialConnectError");
    _readStreamController.addError(e);
    log("<--BBC.onSerialConnectError");
  }

  @override
  void onSerialIoError(Exception e) {
    log("-->BBC.onSerialIoError");
    _readStreamController.addError(e);
    log("<--BBC.onSerialIoError");
  }

  @override
  void onSerialRead(Uint8List data) {
    log("-->BBC.onSerialRead");
    _readStreamController.add(data);
    log("<--BBC.onSerialRead");
  }



    //// From SerialSocket.java

    static final String _BLUETOOTH_LE_CCCD           = "00002902-0000-1000-8000-00805f9b34fb";
    static final String _BLUETOOTH_LE_CC254X_SERVICE = "0000ffe0-0000-1000-8000-00805f9b34fb";
    static final String _BLUETOOTH_LE_CC254X_CHAR_RW = "0000ffe1-0000-1000-8000-00805f9b34fb";
    static final String _BLUETOOTH_LE_NRF_SERVICE    = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
    static final String _BLUETOOTH_LE_NRF_CHAR_RW2   = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // read on microbit, write on adafruit
    static final String _BLUETOOTH_LE_NRF_CHAR_RW3   = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
    static final String _BLUETOOTH_LE_MICROCHIP_SERVICE    = "49535343-FE7D-4AE5-8FA9-9FAFD205E455";
    static final String _BLUETOOTH_LE_MICROCHIP_CHAR_RW    = "49535343-1E4D-4BD9-BA61-23C647249616";
    static final String _BLUETOOTH_LE_MICROCHIP_CHAR_W     = "49535343-8841-43F4-A8D4-ECBE34729BB3";

    // https://play.google.com/store/apps/details?id=com.telit.tiosample
    // https://www.telit.com/wp-content/uploads/2017/09/TIO_Implementation_Guide_r6.pdf
    static final String _BLUETOOTH_LE_TIO_SERVICE          = "0000FEFB-0000-1000-8000-00805F9B34FB";
    static final String _BLUETOOTH_LE_TIO_CHAR_TX          = "00000001-0000-1000-8000-008025000000"; // WNR
    static final String _BLUETOOTH_LE_TIO_CHAR_RX          = "00000002-0000-1000-8000-008025000000"; // N
    static final String _BLUETOOTH_LE_TIO_CHAR_TX_CREDITS  = "00000003-0000-1000-8000-008025000000"; // W
    static final String _BLUETOOTH_LE_TIO_CHAR_RX_CREDITS  = "00000004-0000-1000-8000-008025000000"; // I

    static final int _MAX_MTU = 512; // BLE standard does not limit, some BLE 4.2 devices support 251, various source say that Android has max 512
    static final int _DEFAULT_MTU = 23;
    static final String _TAG = "SerialSocket";

    final List<Uint8List> _writeBuffer = <Uint8List>[];

    SerialListener? _listener;
    _DeviceDelegate? _delegate;
    String? _readService, _writeService;
    String? _readCharacteristic, _writeCharacteristic;

    bool _writePending = false;
    bool _canceled = false;
    bool _connected = false;
    int _payloadSize = _DEFAULT_MTU-3;

    List<StreamSubscription> _stuffToCancel = [];

    Future<void> disconnect() async {
        log("-->BBC.disconnect");
        _listener = null; // ignore remaining data and errors
        // address = null;
        _canceled = true;
        for (var s in _stuffToCancel) {
          unawaited(s.cancel().catchError((e) {}));
        }
        _servicesTimeout.reset();
        _services = {};
        // synchronized (_writeBuffer)
        {
            _writePending = false;
            _writeBuffer.clear();
        }
        _readCharacteristic = null;
        _readService = null;
        _writeCharacteristic = null;
        _writeService = null;
        if (_delegate != null)
            _delegate!.disconnect();
        try {
            await BluetoothCallbackTracker.INSTANCE.disconnect(address);
        } catch (e, s) {
          // Eh, ignore errors here I guess
        }
        _connected = false;
        _connectedStreamController.add(_connected);
        log("<--BBC.disconnect");
    }

    /**
     * connect-success and most connect-errors are returned asynchronously to listener
     */
    Future<void> connect(SerialListener listener) async { // This was basically copied into the constructor
        log("-->BBC.connect");
        if(_connected || _manuallyDisconnected) // I don't know what the result would be of permitting you to reconnect; it seems like the original code was written not to allow that.
            throw Exception("already connected");
        _canceled = false;
        this._listener = listener;
        log("connect $address");
        await BluetoothCallbackTracker.INSTANCE.connect(address);
        // continues asynchronously in onPairingBroadcastReceive() and onConnectionStateChange()
        log("<--BBC.connect");
    }

    Map<String, Set<String>> _services = {};

    final _servicesTimeout = CountdownTimer(); //THINK Not sure if class field, or local var

    Future<void> _onConnectionStateChange(String deviceId, BlueConnectionState state) async {
        log("-->BBC._onConnectionStateChange");
        print('_handleConnectionChange $deviceId, $state');
        // status directly taken from gat_api.h, e.g. 133=0x85=GATT_ERROR ~= timeout
        if (state == BlueConnectionState.connected) {
            log("connect status $state, discoverServices");
            try {
                _stuffToCancel.add(BluetoothCallbackTracker.INSTANCE.subscribeForServiceResults(deviceId).listen((event) {
                    log("-->BBC._onConnectionStateChange.service discovered $event");
                    var cs = _services[event.a];
                    if (cs == null) {
                        cs = Set();
                        _services[event.a] = cs;
                    }
                    cs.addAll(event.b);
                    _servicesTimeout.delay(Duration(milliseconds: 500)).then((value) {
                        log("-->BBC._onConnectionStateChange.@serviceDiscovered.@timeout");
                        _onServicesDiscovered();
                        log("<--BBC._onConnectionStateChange.@serviceDiscovered.@timeout");
                    }, onError: (e) {});
                    log("<--BBC._onConnectionStateChange.service discovered");
                }));
                await BluetoothCallbackTracker.INSTANCE.discoverServices(deviceId); //CHECK This sometimes...just doesn't do anything.  >8|
            } catch (e, s) {
                _onSerialConnectError(Exception("discoverServices failed"));
            }
        } else if (state == BlueConnectionState.disconnected) {
            if (_connected)
                _onSerialIoError     (Exception("gatt disconnected"));
            else
                _onSerialConnectError(Exception("gatt failed to connect"));
        } else {
            log("unknown connect state $state");
        }
        // continues asynchronously in onServicesDiscovered()
        log("<--BBC._onConnectionStateChange");
    }

    void _onServicesDiscovered() {
        log("-->BBC._onServicesDiscovered");
        log("servicesDiscovered, $_services");
        if (_canceled) {
            log("<--BBC._onServicesDiscovered");
            return;
        }
        _connectCharacteristics1();
        log("<--BBC._onServicesDiscovered");
    }

    void _connectCharacteristics1() {
        log("-->BBC._connectCharacteristics1");
        bool sync = true;
        _writePending = false;
        for (String gattService in _services.keys) {
            if (uuidAisaB(gattService, _BLUETOOTH_LE_CC254X_SERVICE))
                _delegate = new _Cc245XDelegate(this);
            if (uuidAisaB(gattService, _BLUETOOTH_LE_MICROCHIP_SERVICE))
                _delegate = new _MicrochipDelegate(this);
            if (uuidAisaB(gattService, _BLUETOOTH_LE_NRF_SERVICE))
                _delegate = new _NrfDelegate(this);
            if (uuidAisaB(gattService, _BLUETOOTH_LE_TIO_SERVICE))
                _delegate = new _TelitDelegate(this);

            if(_delegate != null) {
                sync = _delegate!.connectCharacteristics(gattService);
                break;
            }
        }
        if(_canceled) {
            log("<--BBC._connectCharacteristics1");
            return;
        }
        if(_delegate==null || _readCharacteristic==null || _writeCharacteristic==null) {
            for (String gattService in _services.keys) {
                log("service $gattService");
                for(String characteristic in _services[gattService] ?? [])
                    log("characteristic $characteristic");
            }
            _onSerialConnectError(Exception("no serial profile found"));
            log("<--BBC._connectCharacteristics1");
            return;
        }
        if(sync)
            _connectCharacteristics2();
        log("<--BBC._connectCharacteristics1");
    }

    void _connectCharacteristics2() {
        log("-->BBC._connectCharacteristics2");
        if (false) {
            //RAINY Try to set max MTU.  But I don't trust QuickBlue's one-channel notification stream under the hood.
            // log("request max MTU");
            // if (!gatt.requestMtu(_MAX_MTU))
            //     _onSerialConnectError(Exception("request MTU failed"));
            // // continues asynchronously in onMtuChanged
            // onMtuChanged();
        } else {
            _connectCharacteristics3();
        }
        log("<--BBC._connectCharacteristics2");
    }

    void onMtuChanged(int mtu, bool success) {
        log("-->BBC.onMtuChanged $mtu $success");
        log("mtu size $mtu");
        if(success) {
            _payloadSize = mtu - 3;
            log("payload size $_payloadSize");
        }
        _connectCharacteristics3();
        log("<--BBC.onMtuChanged");
    }

    void _connectCharacteristics3() {
        log("-->BBC._connectCharacteristics3");
        // // QuickBlue doesn't support getting characteristic properties
        // int writeProperties = _writeCharacteristic.getProperties();
        // if((writeProperties & (BluetoothGattCharacteristic.PROPERTY_WRITE +     // Microbit,HM10-clone have WRITE
        //         BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE)) ==0) { // HM10,TI uart,Telit have only WRITE_NO_RESPONSE
        //     _onSerialConnectError(Exception("write characteristic not writable"));
        //     return;
        // }

        // I've opted for async, here, but it's possible it should have been sync
        _stuffToCancel.add(BluetoothCallbackTracker.INSTANCE.subscribeForCharacteristicValues(address, _readService!, _readCharacteristic!).listen((event) async {
            await onCharacteristicChanged(_readCharacteristic!, event);
        }, onError: (e, s) {
            _onSerialConnectError(Exception("no notification for read characteristic, or read error"));
        })); //THINK Maybe onDone?
        log("enable read notification....");
        BluetoothCallbackTracker.INSTANCE.setNotifiable(address, _readService!, _readCharacteristic!, BleInputProperty.notification).then((value) async {
            onDescriptorWrite(_readCharacteristic!, true);
        }, onError: (e, s) async {
            log("set notifiable readCharacteristic error, trying indication");
            unawaited(BluetoothCallbackTracker.INSTANCE.setNotifiable(address, _readService!, _readCharacteristic!, BleInputProperty.indication).then((value) async {
                onDescriptorWrite(_readCharacteristic!, true);
            }, onError: (e, s) async {
                log("set notifiable readCharacteristic error $e $s");
                onDescriptorWrite(_readCharacteristic!, false);
                _onSerialConnectError(Exception("no notification for read characteristic")); // This may be redundant
            }));
        });
        log("<--BBC._connectCharacteristics3");
    }

    void onDescriptorWrite(String characteristic, bool success) {
        log("-->BBC.onDescriptorWrite $characteristic $success");
        _delegate!.onDescriptorWrite(characteristic, success);
        if(_canceled) {
            log("<--BBC.onDescriptorWrite");
            return;
        }
        if(uuidsEqual(characteristic, _readCharacteristic)) {
            log("writing read characteristic descriptor finished, success=$success");
            if (!success) {
                _onSerialConnectError(Exception("write descriptor failed"));
            } else {
                // onCharacteristicChanged with incoming data can happen after writeDescriptor(ENABLE_INDICATION/NOTIFICATION)
                // before confirmed by this method, so receive data can be shown before device is shown as 'Connected'.
                _onSerialConnect();
                _connected = true;
                _connectedStreamController.add(_connected);
                log("connected");
            }
        }
        log("<--BBC.onDescriptorWrite");
    }

    /*
     * read
     */
    Future<void> onCharacteristicChanged(String characteristic, Uint8List data) async {
        log("-->BBC.onCharacteristicChanged");
        if(_canceled) {
            log("<--BBC.onCharacteristicChanged");
            return;
        }
        await _delegate!.onCharacteristicChanged(characteristic, data);
        if(_canceled) {
            log("<--BBC.onCharacteristicChanged");
            return;
        }
        if(uuidsEqual(characteristic, _readCharacteristic)) { // NOPMD - test object identity
            _onSerialRead(data);
            log("read, len=${data.length}");
        }
        log("<--BBC.onCharacteristicChanged");
    }

    /*
     * write
     */
    Future<void> write(Uint8List data) async {
        log("-->BBC.write");
        if(_canceled || !_connected || _writeCharacteristic == null)
            throw Exception("not connected");
        Uint8List? data0;
        // synchronized (writeBuffer) {
            if(data.length <= _payloadSize) {
                data0 = data;
            } else {
                data0 = data.sublist(0, _payloadSize);
            }
            if(!_writePending && _writeBuffer.isEmpty && _delegate!.canWrite()) {
                _writePending = true;
            } else {
                _writeBuffer.add(data0);
                log("write queued, len=${data0.length}");
                data0 = null;
            }
            if(data.length > _payloadSize) {
                for(int i=1; i<(data.length+_payloadSize-1)~/_payloadSize; i++) {
                    int from = i*_payloadSize;
                    int to = math.min(from+_payloadSize, data.length);
                    _writeBuffer.add(data.sublist(from, to));
                    log("write queued, len=${to-from}");
                }
            }
        // }
        if(data0 != null) {
            final ws = _writeService!;
            final wc = _writeCharacteristic!;
            unawaited(BluetoothCallbackTracker.INSTANCE.subscribeForWroteCharacteristic(address, ws, wc).first.then((value) async {
                await onCharacteristicWrite(wc, value.b);
            }));
            final data1 = data0;
            unawaited(BluetoothCallbackTracker.INSTANCE.writeValue(address, ws, wc, data0).then((value) {
                log("write started, len=${data1.length}");
            }, onError: (e, s) {
                _onSerialIoError(Exception("write failed"));
            }));
        }
        // continues asynchronously in onCharacteristicWrite()
        log("<--BBC.write");
    }

    // Note - this is for when we WRITE to ble
    //RAINY Probably should add service param
    //DUMMY Oh - this is gonna need changed for XString, too - uuidAisaB
    Future<void> onCharacteristicWrite(String characteristic, bool success) async {
        log("-->BBC.onCharacteristicWrite $characteristic $success");
        if(_canceled || !_connected || _writeCharacteristic == null) {
            log("<--BBC.onCharacteristicWrite");
            return;
        }
        if(!success) {
            _onSerialIoError(Exception("write failed"));
            log("<--BBC.onCharacteristicWrite");
            return;
        }
        _delegate!.onCharacteristicWrite(characteristic, success);
        if(_canceled) {
            log("<--BBC.onCharacteristicWrite");
            return;
        }
        if(uuidsEqual(characteristic, _writeCharacteristic)) { // NOPMD - test object identity
            log("write finished, success=$success");
            await _writeNext();
        }
        log("<--BBC.onCharacteristicWrite");
    }

    Future<void> _writeNext() async {
        log("-->BBC._writeNext");
        final Uint8List data;
        // synchronized (writeBuffer) {
            if (!_writeBuffer.isEmpty && _delegate!.canWrite()) {
                _writePending = true;
                data = _writeBuffer.removeAt(0);
            } else {
                _writePending = false;
                log("<--BBC._writeNext");
                return;
            }
        // }
        try {
            final ws = _writeService!;
            final wc = _writeCharacteristic!;
            unawaited(BluetoothCallbackTracker.INSTANCE.subscribeForWroteCharacteristic(address, ws, wc).first.then((value) async {
              await onCharacteristicWrite(wc, value.b);
            }));
            await BluetoothCallbackTracker.INSTANCE.writeValue(address, ws, wc, data);
            log("write started, len=${data.length}");
        } catch (e, s) {
            _onSerialIoError(Exception("write failed"));
        }
        log("<--BBC._writeNext");
    }

    /**
     * Call out to SerialListener
     */
    void _onSerialConnect() {
        log("-->BBC._onSerialConnect");
        if (_listener != null)
            _listener!.onSerialConnect();
        log("<--BBC._onSerialConnect");
    }

    void _onSerialConnectError(Exception e) {
        log("-->BBC._onSerialConnectError");
        _canceled = true;
        _connected = false; //THINK I'm not entirely sure adding this here won't cause unintended problems, buuuut....
        _connectedStreamController.add(_connected);
        if (_listener != null)
            _listener!.onSerialConnectError(e);
        unawaited(close()); //CHECK I'm not sure about adding this, but it feels like a good idea
        log("<--BBC._onSerialConnectError");
    }

    void _onSerialRead(Uint8List data) {
        log("-->BBC._onSerialRead");
        if (_listener != null)
            _listener!.onSerialRead(data);
        log("<--BBC._onSerialRead");
    }

    void _onSerialIoError(Exception e) {
        log("-->BBC._onSerialIoError");
        _writePending = false;
        _canceled = true;
        //DITTO
        _connected = false;
        _connectedStreamController.add(_connected);
        if (_listener != null)
            _listener!.onSerialIoError(e);
        unawaited(close()); //CHECK I'm not sure about adding this, but it feels like a good idea
        log("<--BBC._onSerialIoError");
    }
}

/**
 * delegate device specific behaviour to inner class
 */
class _DeviceDelegate {
    final BleBluetoothConnection owner;

    _DeviceDelegate(this.owner);

    bool connectCharacteristics(String service) { return true; }
    // following methods only overwritten for Telit devices
    void onDescriptorWrite(String characteristic, bool success) { /*nop*/ }
    Future<void> onCharacteristicChanged(String c, Uint8List data) async { /*nop*/ }
    void onCharacteristicWrite(String c, bool success) { /*nop*/ }
    bool canWrite() { return true; }
    void disconnect() {/*nop*/ }
}

/**
 * device delegates
 */

class _Cc245XDelegate extends _DeviceDelegate {
    _Cc245XDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(String service) {
        log("-->_Cc245XDelegate.connectCharacteristics");
        log("service cc254x uart");
        owner._readCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_CC254X_CHAR_RW;
        owner._readService = service;
        owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_CC254X_CHAR_RW;
        owner._writeService = service;
        log("<--_Cc245XDelegate.connectCharacteristics");
        return true;
    }
}

class _MicrochipDelegate extends _DeviceDelegate {
    _MicrochipDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(String service) {
        log("-->_MicrochipDelegate.connectCharacteristics");
        log("service microchip uart");
        owner._readCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_RW;
        owner._readService = service;
        owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_W;
        owner._writeService = service;
        if (!(owner._services[service]?.any((c) => uuidAisaB(c, owner._writeCharacteristic!)) ?? false)) {
            owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_RW;
            owner._writeService = service;
        }
        log("<--_MicrochipDelegate.connectCharacteristics");
        return true;
    }
}

class _NrfDelegate extends _DeviceDelegate {
    _NrfDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(String service) {
        log("-->_NrfDelegate.connectCharacteristics");
        log("service nrf uart");
        String rw2 = BleBluetoothConnection._BLUETOOTH_LE_NRF_CHAR_RW2;
        String rw3 = BleBluetoothConnection._BLUETOOTH_LE_NRF_CHAR_RW3;
        // if (rw2 != null && rw3 != null) {
        //     int rw2prop = rw2.getProperties();
        //     int rw3prop = rw3.getProperties();
        //     bool rw2write = (rw2prop & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0;
        //     bool rw3write = (rw3prop & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0;
        //     log("characteristic properties $rw2prop/$rw3prop");
        //     if (rw2write && rw3write) {
        //         owner._onSerialConnectError(Exception("multiple write characteristics ($rw2prop/$rw3prop)"));
        //     } else if (rw2write) {
                //DUMMY We don't really have a way of checking whether a characteristic is writable, atm, aside from writing to it.  So this will probably fail in some cases.
                owner._writeCharacteristic = rw2;
                owner._writeService = service;
                owner._readCharacteristic = rw3;
                owner._readService = service;
        //     } else if (rw3write) {
        //         owner._writeCharacteristic = rw3;
        //         owner._writeService = service;
        //         owner._readCharacteristic = rw2;
        //         owner._readService = service;
        //     } else {
        //         owner._onSerialConnectError(Exception("no write characteristic ($rw2prop/$rw3prop)"));
        //     }
        // }
        log("<--_NrfDelegate.connectCharacteristics");
        return true;
    }
}

class _TelitDelegate extends _DeviceDelegate {
    String? _readCreditsCharacteristic, _writeCreditsCharacteristic;
    int _readCredits = 0;
    int _writeCredits = 0;

    _TelitDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(String service) {
        log("-->_TelitDelegate.connectCharacteristics");
        log("service telit tio 2.0");
        _readCredits = 0;
        _writeCredits = 0;
        owner._readCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_RX;
        owner._readService = service;
        owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_TX;
        owner._writeService = service;
        _readCreditsCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_RX_CREDITS;
        _writeCreditsCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_TX_CREDITS;
        if (!(owner._services[service]?.any((c) => uuidAisaB(c, owner._readCharacteristic!)) ?? false)) {
            owner._onSerialConnectError(Exception("read characteristic not found"));
            log("<--_TelitDelegate.connectCharacteristics");
            return false;
        }
        if (!(owner._services[service]?.any((c) => uuidAisaB(c, owner._writeCharacteristic!)) ?? false)) {
            owner._onSerialConnectError(Exception("write characteristic not found"));
            log("<--_TelitDelegate.connectCharacteristics");
            return false;
        }
        if (!(owner._services[service]?.any((c) => uuidAisaB(c, _readCreditsCharacteristic!)) ?? false)) {
            owner._onSerialConnectError(Exception("read credits characteristic not found"));
            log("<--_TelitDelegate.connectCharacteristics");
            return false;
        }
        if (!(owner._services[service]?.any((c) => uuidAisaB(c, _writeCreditsCharacteristic!)) ?? false)) {
            owner._onSerialConnectError(Exception("write credits characteristic not found"));
            log("<--_TelitDelegate.connectCharacteristics");
            return false;
        }
        owner._stuffToCancel.add(BluetoothCallbackTracker.INSTANCE.subscribeForCharacteristicValues(owner.address, service, _readCreditsCharacteristic!).listen((event) async {
            await owner.onCharacteristicChanged(_readCreditsCharacteristic!, event);
        }, onError: (e, s) {
            owner._onSerialConnectError(Exception("no notification for read characteristic, or read error"));
        })); //THINK Maybe onDone?
        BluetoothCallbackTracker.INSTANCE.setNotifiable(owner.address, service, _readCreditsCharacteristic!, BleInputProperty.indication).then((value) {
            owner.onDescriptorWrite(_readCreditsCharacteristic!, true);
        }, onError: (error, stackTrace) {
            owner.onDescriptorWrite(_readCreditsCharacteristic!, false);
            owner._onSerialConnectError(Exception("no notification for read credits characteristic"));
        });
        log("<--_TelitDelegate.connectCharacteristics");
        return false;
        // continues asynchronously in connectCharacteristics2
    }

    @override
    void onDescriptorWrite(String characteristic, bool success) {
        log("-->_TelitDelegate.onDescriptorWrite $characteristic $success");
        if(uuidsEqual(characteristic, _readCreditsCharacteristic)) {
            log("writing read credits characteristic descriptor finished, success=$success");
            if (!success) {
                owner._onSerialConnectError(Exception("write credits descriptor failed"));
            } else {
                owner._connectCharacteristics2();
            }
        }
        if(uuidsEqual(characteristic, owner._readCharacteristic)) {
            log("writing read characteristic descriptor finished, success=$success");
            if (success) {
                // owner._readCharacteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
                // owner._writeCharacteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
                unawaited(grantReadCredits()); // The asyncness of this call varies, but I THINK this should be ok
                // grantReadCredits includes gatt.writeCharacteristic(writeCreditsCharacteristic)
                // but we do not have to wait for confirmation, as it is the last write of connect phase.
                //CHECK Does it matter that we'll probably get a response?
            }
        }
        log("<--_TelitDelegate.onDescriptorWrite");
    }

    @override
    Future<void> onCharacteristicChanged(String characteristic, Uint8List data) async {
        log("-->_TelitDelegate.onCharacteristicChanged $characteristic");
        if(uuidsEqual(characteristic, _readCreditsCharacteristic)) { // NOPMD - test object identity
            int newCredits = data[0];
            // synchronized (writeBuffer) {
                _writeCredits += newCredits;
            // }
            log("got write credits +$newCredits =$_writeCredits");

            if (!owner._writePending && owner._writeBuffer.isNotEmpty) {
                log("resume blocked write");
                await owner._writeNext();
            }
        }
        if(uuidsEqual(characteristic, owner._readCharacteristic)) { // NOPMD - test object identity
            await grantReadCredits();
            log("read, credits=$_readCredits");
        }
        log("<--_TelitDelegate.onCharacteristicChanged");
    }

    @override
    void onCharacteristicWrite(String characteristic, bool success) {
        log("-->_TelitDelegate.onCharacteristicWrite $characteristic $success");
        if(uuidsEqual(characteristic, owner._writeCharacteristic)) { // NOPMD - test object identity
            // synchronized (owner._writeBuffer) {
                if (_writeCredits > 0)
                    _writeCredits -= 1;
            // }
            log("write finished, credits=$_writeCredits");
        }
        if(uuidsEqual(characteristic, _writeCreditsCharacteristic)) { // NOPMD - test object identity
            log("write credits finished, success=$success");
        }
        log("<--_TelitDelegate.onCharacteristicWrite");
    }

    @override
    bool canWrite() {
        log("-->_TelitDelegate.canWrite");
        if(_writeCredits > 0) {
            log("<--_TelitDelegate.canWrite");
            return true;
        }
        log("no write credits");
        log("<--_TelitDelegate.canWrite");
        return false;
    }

    @override
    void disconnect() {
        log("-->_TelitDelegate.disconnect");
        _readCreditsCharacteristic = null;
        _writeCreditsCharacteristic = null;
        log("<--_TelitDelegate.disconnect");
    }

    Future<void> grantReadCredits() async {
        log("-->_TelitDelegate.grantReadCredits");
        final int minReadCredits = 16;
        final int maxReadCredits = 64;
        if(_readCredits > 0)
            _readCredits -= 1;
        if(_readCredits <= minReadCredits) {
            int newCredits = maxReadCredits - _readCredits;
            _readCredits += newCredits;
            Uint8List data = Uint8List.fromList([newCredits]);
            log("grant read credits +$newCredits =$_readCredits");
            try {
                final ws = owner._writeService!!;
                final wc = _writeCreditsCharacteristic!;
                unawaited(BluetoothCallbackTracker.INSTANCE.subscribeForWroteCharacteristic(owner.address, ws, wc).first.then((value) async {
                  //CHECK Does this get called if write is withoutResponse?
                  await owner.onCharacteristicWrite(wc, value.b);
                }));
                await BluetoothCallbackTracker.INSTANCE.writeValue(owner.address, ws, wc, data, withoutResponse: true);
            } catch (e, s) {
                if(owner._connected)
                    owner._onSerialIoError(Exception("write read credits failed"));
                else
                    owner._onSerialConnectError(Exception("write read credits failed"));
            }
        }
        log("<--_TelitDelegate.grantReadCredits");
    }
}

abstract class SerialListener {
    void onSerialConnect      ();
    void onSerialConnectError (Exception e);
    void onSerialRead         (Uint8List data); // data coming in from BLE
    void onSerialIoError      (Exception e);
}

// Almost entirely copied from BluetoothStreamSink
class BleBluetoothStreamSink<Uint8List> extends BluetoothStreamSink<Uint8List> {
  var delegate = StreamController<Uint8List>();

  BleBluetoothStreamSink() : super(null);

  /// Adds raw bytes to the output sink.
  ///
  /// The data is sent almost immediately, but if you want to be sure,
  /// there is `this.allSent` that provides future which completes when
  /// all added data are sent.
  ///
  /// You should use some encoding to send string, for example `ascii.encode('Hello!')` or `utf8.encode('Cześć!)`.
  ///
  /// Might throw `StateError("Not connected!")` if not connected.
  @override
  void add(Uint8List data) {
    log("-->BBSS.add");
    if (!isConnected) {
      throw StateError("Not connected!");
    }

    _chainedFutures = _chainedFutures.then((_) async {
      if (!isConnected) {
        throw StateError("Not connected!");
      }

      delegate.add(data);
    }).catchError((e) {
      this.exception = e;
      close();
    });
    log("<--BBSS.add");
  }
}