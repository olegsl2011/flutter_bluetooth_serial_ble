import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial_ble/BluetoothConnectionTracker.dart';
import 'package:flutter_bluetooth_serial_ble/CountdownTimer.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:quick_blue/quick_blue.dart';

//DUMMY Go back through and check for unused functions; those are probably ones I forgot to use in callbacks

//DUMMY I don't yet know what to do about the original interleaving of data and errors; streams don't support that

class BleBluetoothConnection implements SerialListener, BluetoothConnection {
  bool _manuallyDisconnected = false;
  final String address;

  BleBluetoothConnection(this.address) {
    _readStreamController = StreamController<Uint8List>();
    input = _readStreamController.stream;
    _writeStreamController.delegate.stream.listen((data) async {
      await write(data);
    });

    BluetoothCallbackTracker.INSTANCE.subscribeForConnectionResults(address).listen((event) {
      _onConnectionStateChange(address, event);
    });

    BluetoothCallbackTracker.INSTANCE.connect(address);
    //DUMMY Other callbacks?
    //DUMMY There was a disconnectCallbackReceiver....

    _listener = this;

    //DUMMY Hang on, I think this is maybe expected to be connected on return?
  }


  //// BluetoothConnection, mostly copied

  late StreamController<Uint8List> _readStreamController;

  @override
  late final Stream<Uint8List>? input;

  final _writeStreamController = BleBluetoothStreamSink<Uint8List>();

  @override
  late BluetoothStreamSink<Uint8List> output = _writeStreamController;

  @override
  bool get isConnected => _connected; //DUMMY Resolve conflict with output.connected

  /// Should be called to make sure the connection is closed and resources are freed (sockets/channels).
  void dispose() {
    finish();
  }

  /// Closes connection (rather immediately), in result should also disconnect.
  @override
  Future<void> close() async {
    await disconnect();
    await Future.wait([
      output.close(),
      (!_readStreamController.isClosed)
          ? _readStreamController.close()
          : Future.value(/* Empty future */)
    ], eagerError: true);
  }

  /// Closes connection (rather immediately), in result should also disconnect.
  @Deprecated('Use `close` instead')
  Future<void> cancel() => this.close();

  /// Closes connection (rather gracefully), in result should also disconnect.
  Future<void> finish() async {
    await output.allSent;
    await close();
  }



  //// SerialListener

  @override
  void onSerialConnect() {
    output.isConnected = true;
    //DUMMY Do we need to do anything else?
  }

  @override
  void onSerialConnectError(Exception e) {
    _readStreamController.addError(e);
    //DUMMY Do we need to do anything else?
  }

  @override
  void onSerialIoError(Exception e) {
    _readStreamController.addError(e);
    //DUMMY Do we need to do anything else?
  }

  @override
  void onSerialRead(Uint8List data) {
    _readStreamController.add(data);
    //DUMMY Do we need to do anything else?
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
    String? _readService, _writeService; //DUMMY Make sure to set these
    String? _readCharacteristic, _writeCharacteristic;

    bool _writePending = false;
    bool _canceled = false;
    bool _connected = false;
    int _payloadSize = _DEFAULT_MTU-3;

    Future<void> disconnect() async {
        log("disconnect");
        _listener = null; // ignore remaining data and errors
        // address = null;
        _canceled = true;
        _servicesTimeout.reset();
        _services = {};
        // synchronized (_writeBuffer)
        {
            _writePending = false;
            _writeBuffer.clear();
        }
        _readCharacteristic = null;
        _writeCharacteristic = null;
        if (_delegate != null)
            _delegate!.disconnect();
        //THINK ...Should it await?
        await BluetoothCallbackTracker.INSTANCE.disconnect(address);
        _connected = false;
        //DUMMY Unregister disconnectBroadcastReceiver, whatever that ends up meaning
    }

    /**
     * connect-success and most connect-errors are returned asynchronously to listener
     */
    Future<void> connect(SerialListener listener) async {
        if(_connected || _manuallyDisconnected) // I don't know what the result would be of permitting you to reconnect; it seems like the original code was written not to allow that.
            throw Exception("already connected");
        _canceled = false;
        this._listener = listener;
        //DUMMY There was ALSO a disconnectBroadcastReceiver here??
        log("connect $address");
        await BluetoothCallbackTracker.INSTANCE.connect(address);
        // continues asynchronously in onPairingBroadcastReceive() and onConnectionStateChange()
    }

    //SHAME Turns out you're allowed to have multiple characteristics with the same UUID (bleh), and this does not accommodate that.
    Map<String, Set<String>> _services = {};

    final _servicesTimeout = CountdownTimer(); //THINK Not sure if class field, or local var

    Future<void> _onConnectionStateChange(String deviceId, BlueConnectionState state) async {
        print('_handleConnectionChange $deviceId, $state');
        // status directly taken from gat_api.h, e.g. 133=0x85=GATT_ERROR ~= timeout
        if (state == BlueConnectionState.connected) {
            log("connect status $state, discoverServices");
            try {
              //DUMMY We should probably cancel this in `disconnect` and so forth
              BluetoothCallbackTracker.INSTANCE.subscribeForServiceResults(deviceId).listen((event) {
                var cs = _services[event.a];
                if (cs == null) {
                  cs = Set();
                  _services[event.a] = cs;
                }
                cs.addAll(event.b);
                _servicesTimeout.delay(Duration(milliseconds: 500)).then((value) {
                  _onServicesDiscovered();
                }, onError: (e) {});
              });
              await BluetoothCallbackTracker.INSTANCE.discoverServices(deviceId);
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
    }

    void _onServicesDiscovered() {
        log("servicesDiscovered, $_services");
        if (_canceled)
            return;
        _connectCharacteristics1();
    }

    void _connectCharacteristics1() {
        bool sync = true;
        _writePending = false;
        for (String gattService in _services.keys) {
            if (gattService == _BLUETOOTH_LE_CC254X_SERVICE)
                _delegate = new _Cc245XDelegate(this);
            if (gattService == _BLUETOOTH_LE_MICROCHIP_SERVICE)
                _delegate = new _MicrochipDelegate(this);
            if (gattService == _BLUETOOTH_LE_NRF_SERVICE)
                _delegate = new _NrfDelegate(this);
            if (gattService == _BLUETOOTH_LE_TIO_SERVICE)
                _delegate = new _TelitDelegate(this);

            if(_delegate != null) {
                sync = _delegate!.connectCharacteristics(gattService);
                break;
            }
        }
        if(_canceled)
            return;
        if(_delegate==null || _readCharacteristic==null || _writeCharacteristic==null) {
            for (String gattService in _services.keys) {
                log("service $gattService");
                for(String characteristic in _services[gattService] ?? [])
                    log("characteristic $characteristic");
            }
            _onSerialConnectError(Exception("no serial profile found"));
            return;
        }
        if(sync)
            _connectCharacteristics2();
    }

    void _connectCharacteristics2() {
        if (false) {
            //DUMMY Try to set max MTU.  But I don't trust QuickBlue's one-channel notification stream under the hood.
            // log("request max MTU");
            // if (!gatt.requestMtu(_MAX_MTU))
            //     _onSerialConnectError(Exception("request MTU failed"));
            // // continues asynchronously in onMtuChanged
            // onMtuChanged();
        } else {
            _connectCharacteristics3();
        }
    }

    void onMtuChanged(int mtu, bool success) {
        //DUMMY Integrate
        log("mtu size $mtu");
        if(success) {
            _payloadSize = mtu - 3;
            log("payload size $_payloadSize");
        }
        _connectCharacteristics3();
    }

    void _connectCharacteristics3() {
        // // QuickBlue doesn't support getting characteristic properties
        // int writeProperties = _writeCharacteristic.getProperties();
        // if((writeProperties & (BluetoothGattCharacteristic.PROPERTY_WRITE +     // Microbit,HM10-clone have WRITE
        //         BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE)) ==0) { // HM10,TI uart,Telit have only WRITE_NO_RESPONSE
        //     _onSerialConnectError(Exception("write characteristic not writable"));
        //     return;
        // }

        // I've opted for async, here, but it's possible it should have been sync
        //CHECK Is this really the only char subscription we make?  Really??
        BluetoothCallbackTracker.INSTANCE.subscribeForCharacteristicValues(address, _readCharacteristic!).listen((event) {
            onCharacteristicChanged(_readCharacteristic!, event);
        }).onError((e, s) {
            _onSerialConnectError(Exception("no notification for read characteristic, or read error"));
        }); //THINK Maybe onDone?
        //CHECK Should this fall back to INDICATE on failure?
        log("enable read notification....");
        BluetoothCallbackTracker.INSTANCE.setNotifiable(address, _readService!, _readCharacteristic!, BleInputProperty.notification).then((value) async {
            onDescriptorWrite(_readCharacteristic!, true);
        }, onError: (e, s) async {
            onDescriptorWrite(_readCharacteristic!, false);
            _onSerialConnectError(Exception("no notification for read characteristic")); // This may be redundant
        });
    }

    void onDescriptorWrite(String characteristic, bool success) {
        _delegate!.onDescriptorWrite(characteristic, success);
        if(_canceled)
            return;
        if(characteristic == _readCharacteristic) {
            log("writing read characteristic descriptor finished, success=$success");
            if (!success) {
                _onSerialConnectError(Exception("write descriptor failed"));
            } else {
                // onCharacteristicChanged with incoming data can happen after writeDescriptor(ENABLE_INDICATION/NOTIFICATION)
                // before confirmed by this method, so receive data can be shown before device is shown as 'Connected'.
                _onSerialConnect();
                _connected = true;
                log("connected");
            }
        }
    }

    /*
     * read
     */
    void onCharacteristicChanged(String characteristic, Uint8List data) { //DUMMY Check this is called where it should be
        if(_canceled)
            return;
        _delegate!.onCharacteristicChanged(characteristic, data);
        if(_canceled)
            return;
        if(characteristic == _readCharacteristic) { // NOPMD - test object identity
            _onSerialRead(data);
            log("read, len=${data.length}");
        }
    }

    /*
     * write
     */
    Future<void> write(Uint8List data) async { //DUMMY Check asyncs
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
                for(int i=1; i<(data.length+_payloadSize-1)/_payloadSize; i++) {
                    int from = i*_payloadSize;
                    int to = math.min(from+_payloadSize, data.length);
                    _writeBuffer.add(data.sublist(from, to));
                    log("write queued, len=${to-from}");
                }
            }
        // }
        if(data0 != null) {
            try {
                //DUMMY "true, if the write operation was initiated successfully" so, make async again I guess
                final wc = _writeCharacteristic!;
                unawaited(BluetoothCallbackTracker.INSTANCE.subscribeForWroteCharacteristic(address, wc).first.then((value) async {
                  await onCharacteristicWrite(wc, value.b);
                }));
                await BluetoothCallbackTracker.INSTANCE.writeValue(address, _writeService!, wc, data0);
                log("write started, len=${data0.length}");
            } catch (e, s) {
                _onSerialIoError(Exception("write failed"));
            }
        }
        // continues asynchronously in onCharacteristicWrite()
        //DUMMY It probably doesn't
    }

    // Note - this is for when we WRITE to ble
    Future<void> onCharacteristicWrite(String characteristic, bool success) async {
        if(_canceled || !_connected || _writeCharacteristic == null)
            return;
        if(!success) {
            _onSerialIoError(Exception("write failed"));
            return;
        }
        _delegate!.onCharacteristicWrite(characteristic, success);
        if(_canceled)
            return;
        if(characteristic == _writeCharacteristic) { // NOPMD - test object identity
            log("write finished, success=$success");
            await _writeNext();
        }
    }

    Future<void> _writeNext() async { //DUMMY propagate async
        final Uint8List data;
        // synchronized (writeBuffer) {
            if (!_writeBuffer.isEmpty && _delegate!.canWrite()) {
                _writePending = true;
                data = _writeBuffer.removeAt(0);
            } else {
                _writePending = false;
                return;
            }
        // }
        try {
            final wc = _writeCharacteristic!;
            unawaited(BluetoothCallbackTracker.INSTANCE.subscribeForWroteCharacteristic(address, wc).first.then((value) async {
              await onCharacteristicWrite(wc, value.b);
            }));
            await BluetoothCallbackTracker.INSTANCE.writeValue(address, _writeService!, wc, data);
            log("write started, len=${data.length}");
        } catch (e, s) {
            _onSerialIoError(Exception("write failed"));
        }
    }

    /**
     * Call out to SerialListener
     */
    void _onSerialConnect() {
        if (_listener != null)
            _listener!.onSerialConnect();
    }

    void _onSerialConnectError(Exception e) {
        _canceled = true;
        if (_listener != null)
            _listener!.onSerialConnectError(e);
    }

    void _onSerialRead(Uint8List data) {
        if (_listener != null)
            _listener!.onSerialRead(data);
    }

    void _onSerialIoError(Exception e) {
        _writePending = false;
        _canceled = true;
        if (_listener != null)
            _listener!.onSerialIoError(e);
    }
}

/**
 * delegate device specific behaviour to inner class
 */
class _DeviceDelegate {
    final BleBluetoothConnection owner;

    _DeviceDelegate(this.owner);

    //DUMMY Check that asyncs called properly
    bool connectCharacteristics(String service) { return true; }
    // following methods only overwritten for Telit devices
    void onDescriptorWrite(String characteristic, bool success) { /*nop*/ }
    void onCharacteristicChanged(String c, Uint8List data) {/*nop*/ }
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
        log("service cc254x uart");
        owner._readCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_CC254X_CHAR_RW;
        owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_CC254X_CHAR_RW;
        return true;
    }
}

class _MicrochipDelegate extends _DeviceDelegate {
    _MicrochipDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(String service) {
        log("service microchip uart");
        owner._readCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_RW;
        owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_W;
        if(owner._services[service]?.contains(owner._writeCharacteristic) ?? false)
            owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_RW;
        return true;
    }
}

class _NrfDelegate extends _DeviceDelegate {
    _NrfDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(String service) {
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
                owner._readCharacteristic = rw3;
        //     } else if (rw3write) {
        //         owner._writeCharacteristic = rw3;
        //         owner._readCharacteristic = rw2;
        //     } else {
        //         owner._onSerialConnectError(Exception("no write characteristic ($rw2prop/$rw3prop)"));
        //     }
        // }
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
        log("service telit tio 2.0");
        _readCredits = 0;
        _writeCredits = 0;
        owner._readCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_RX;
        owner._writeCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_TX;
        _readCreditsCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_RX_CREDITS;
        _writeCreditsCharacteristic = BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_TX_CREDITS;
        if (owner._services[service]?.contains(owner._readCharacteristic) ?? false) {
            owner._onSerialConnectError(Exception("read characteristic not found"));
            return false;
        }
        if (owner._services[service]?.contains(owner._writeCharacteristic) ?? false) {
            owner._onSerialConnectError(Exception("write characteristic not found"));
            return false;
        }
        if (owner._services[service]?.contains(_readCreditsCharacteristic) ?? false) {
            owner._onSerialConnectError(Exception("read credits characteristic not found"));
            return false;
        }
        if (owner._services[service]?.contains(_writeCreditsCharacteristic) ?? false) {
            owner._onSerialConnectError(Exception("write credits characteristic not found"));
            return false;
        }
        //DUMMY What about the callback?
        BluetoothCallbackTracker.INSTANCE.setNotifiable(owner.address, service, _readCreditsCharacteristic!, BleInputProperty.indication).onError((error, stackTrace) {
            owner._onSerialConnectError(Exception("no notification for read credits characteristic"));
        });
        return false;
        // continues asynchronously in connectCharacteristics2
    }

    @override
    void onDescriptorWrite(String characteristic, bool success) { //DUMMY Do we need to call this on failure?
        if(characteristic == _readCreditsCharacteristic) {
            log("writing read credits characteristic descriptor finished, success=$success");
            if (!success) {
                owner._onSerialConnectError(Exception("write credits descriptor failed"));
            } else {
                owner._connectCharacteristics2();
            }
        }
        if(characteristic == owner._readCharacteristic) {
            log("writing read characteristic descriptor finished, success=$success");
            if (success) {
                //CHECK ???
                // owner._readCharacteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
                // owner._writeCharacteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
                grantReadCredits(); //DUMMY async
                // grantReadCredits includes gatt.writeCharacteristic(writeCreditsCharacteristic)
                // but we do not have to wait for confirmation, as it is the last write of connect phase.
                //CHECK Does it matter that we'll probably get a response?
            }
        }
    }

    @override
    Future<void> onCharacteristicChanged(String characteristic, Uint8List data) async {
        if(characteristic == _readCreditsCharacteristic) { // NOPMD - test object identity
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
        if(characteristic == owner._readCharacteristic) { // NOPMD - test object identity
            await grantReadCredits();
            log("read, credits=$_readCredits");
        }
    }

    @override
    void onCharacteristicWrite(String characteristic, bool success) {
        if(characteristic == owner._writeCharacteristic) { // NOPMD - test object identity
            // synchronized (owner._writeBuffer) {
                if (_writeCredits > 0)
                    _writeCredits -= 1;
            // }
            log("write finished, credits=$_writeCredits");
        }
        if(characteristic == _writeCreditsCharacteristic) { // NOPMD - test object identity
            log("write credits finished, success=$success");
        }
    }

    @override
    bool canWrite() {
        if(_writeCredits > 0)
            return true;
        log("no write credits");
        return false;
    }

    @override
    void disconnect() {
        _readCreditsCharacteristic = null;
        _writeCreditsCharacteristic = null;
    }

    Future<void> grantReadCredits() async {
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
                final wc = _writeCreditsCharacteristic!;
                unawaited(BluetoothCallbackTracker.INSTANCE.subscribeForWroteCharacteristic(owner.address, wc).first.then((value) async {
                  await owner.onCharacteristicWrite(wc, value.b);
                }));
                await BluetoothCallbackTracker.INSTANCE.writeValue(owner.address, owner._writeService!, wc, data);
            } catch (e, s) {
                if(owner._connected)
                    owner._onSerialIoError(Exception("write read credits failed"));
                else
                    owner._onSerialConnectError(Exception("write read credits failed"));
            }
        }
    }
}

abstract class SerialListener {
    void onSerialConnect      ();
    void onSerialConnectError (Exception e);
    void onSerialRead         (Uint8List data); // data coming in from BLE
    void onSerialIoError      (Exception e);
}

// Almost entirely copied from BluetoothStreamSink
class BleBluetoothStreamSink<Uint8List> extends StreamSink<Uint8List> implements BluetoothStreamSink<Uint8List> {
  /// Describes is stream connected.
  bool isConnected = true;

  /// Chain of features, the variable represents last of the futures.
  Future<void> _chainedFutures = Future.value(/* Empty future :F */);

  late Future<dynamic> _doneFuture;

  /// Exception to be returend from `done` Future, passed from `add` function or related.
  dynamic exception;

  var delegate = StreamController<Uint8List>();

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
  }

  /// Unsupported - this ouput sink cannot pass errors to platfom code.
  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    throw UnsupportedError(
        "BluetoothConnection output (response) sink cannot receive errors!");
  }

  @override
  Future addStream(Stream<Uint8List> stream) => Future(() async {
    // @TODO ??? `addStream`, "alternating simultaneous addition" problem (read below)
    // If `onDone` were called some time after last `add` to the stream (what is okay),
    // this `addStream` function might wait not for the last "own" addition to this sink,
    // but might wait for last addition at the moment of the `onDone`.
    // This can happen if user of the library would use another `add` related function
    // while `addStream` still in-going. We could do something about it, but this seems
    // not to be so necessary since `StreamSink` specifies that `addStream` should be
    // blocking for other forms of `add`ition on the sink.
    var completer = Completer();
    stream.listen(this.add).onDone(completer.complete);
    await completer.future;
    await _chainedFutures; // Wait last* `add` of the stream to be fulfilled
  });

  @override
  Future close() {
    isConnected = false;
    return this.done;
  }

  @override
  Future get done => _doneFuture;

  /// Returns a future which is completed when the sink sent all added data,
  /// instead of only if the sink got closed.
  ///
  /// Might fail with an error in case if some occured while sending the data.
  /// Typical error could be `StateError("Not connected!")` which could happen
  /// if disconnected in middle of sending (queued) `add`ed data.
  ///
  /// Otherwise, the returned future will complete when either:
  Future get allSent => Future(() async {
    // Simple `await` can't get job done here, because the `_chainedFutures` member
    // in one access time provides last Future, then `await`ing for it allows the library
    // user to add more futures on top of the waited-out Future.
    Future lastFuture;
    do {
      lastFuture = this._chainedFutures;
      await lastFuture;
    } while (lastFuture != this._chainedFutures);

    if (this.exception != null) {
      throw this.exception;
    }

    this._chainedFutures =
        Future.value(); // Just in case if Dart VM is retarded
  });
}