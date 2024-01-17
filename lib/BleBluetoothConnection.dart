import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial_ble/BluetoothConnectionTracker.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:quick_blue/quick_blue.dart';

//DUMMY Go back through and check for unused functions; those are probably ones I forgot to use in callbacks

class BleBluetoothConnection implements BluetoothConnection {
  @override
  Stream<Uint8List>? input;

  @override
  var output;

  final String address;

  BleBluetoothConnection(this.address) {
    QuickBlue.setConnectionHandler(_onConnectionStateChange);

    QuickBlue.connect(address);
    asdf;
  }

  @override
  Future<void> cancel() {
    // TODO: implement cancel
    throw UnimplementedError();
  }

  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  void dispose() {
    // TODO: implement dispose
  }

  @override
  Future<void> finish() {
    // TODO: implement finish
    throw UnimplementedError();
  }

  @override
  // TODO: implement isConnected
  bool get isConnected => throw UnimplementedError();






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

    final List<Uint8List> _writeBuffer;
    final IntentFilter _pairingIntentFilter;
    final BroadcastReceiver _pairingBroadcastReceiver;
    final BroadcastReceiver _disconnectBroadcastReceiver;

    SerialListener _listener;
    DeviceDelegate _delegate;
    BluetoothDevice _device;
    BluetoothGatt _gatt;
    BluetoothGattCharacteristic _readCharacteristic, _writeCharacteristic;

    bool _writePending;
    bool _canceled;
    bool _connected;
    int _payloadSize = _DEFAULT_MTU-3;

    SerialSocket(Context context, BluetoothDevice device) : _writeBuffer = <Uint8List>[] {
        this.device = device;
        pairingIntentFilter = new IntentFilter();
        pairingIntentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
        pairingIntentFilter.addAction(BluetoothDevice.ACTION_PAIRING_REQUEST);
        pairingBroadcastReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                _onPairingBroadcastReceive(context, intent);
            }
        };
        disconnectBroadcastReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if(_listener != null)
                    _listener.onSerialIoError(Exception("background disconnect"));
                disconnect(); // disconnect now, else would be queued until UI re-attached
            }
        };
    }

    void disconnect() {
      asdf;
        log("disconnect");
        _listener = null; // ignore remaining data and errors
        _device = null;
        _canceled = true;
        // synchronized (_writeBuffer)
        {
            _writePending = false;
            _writeBuffer.clear();
        }
        _readCharacteristic = null;
        _writeCharacteristic = null;
        if (_delegate != null)
            _delegate.disconnect();
        if (gatt != null) {
            log("gatt.disconnect");
            gatt.disconnect();
            log("gatt.close");
            try {
                gatt.close();
            } catch (Exception ignored) {}
            gatt = null;
            _connected = false;
        }
        try {
            context.unregisterReceiver(pairingBroadcastReceiver);
        } catch (Exception ignored) {
        }
        try {
            context.unregisterReceiver(disconnectBroadcastReceiver);
        } catch (Exception ignored) {
        }
    }

    /**
     * connect-success and most connect-errors are returned asynchronously to listener
     */
    void connect(SerialListener listener) throws IOException {
        if(_connected || gatt != null)
            throw Exception("already connected");
        _canceled = false;
        this._listener = listener;
        context.registerReceiver(disconnectBroadcastReceiver, new IntentFilter(Constants.INTENT_ACTION_DISCONNECT));
        log("connect $_device");
        context.registerReceiver(pairingBroadcastReceiver, pairingIntentFilter);
        if (Build.VERSION.SDK_INT < 23) {
            log("connectGatt");
            gatt = _device.connectGatt(context, false, this);
        } else {
            log("connectGatt,LE");
            gatt = _device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE);
        }
        if (gatt == null)
            throw Exception("connectGatt failed");
        // continues asynchronously in onPairingBroadcastReceive() and onConnectionStateChange()
    }

    void _onPairingBroadcastReceive() {
      asdf;
        // for ARM Mbed, Microbit, ... use pairing from Android bluetooth settings
        // for HM10-clone, ... pairing is initiated here
        BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
        if(device==null || !device.equals(this._device))
            return;
        switch (intent.getAction()) {
            case BluetoothDevice.ACTION_PAIRING_REQUEST:
                final int pairingVariant = intent.getIntExtra(BluetoothDevice.EXTRA_PAIRING_VARIANT, -1);
                log("pairing request " + pairingVariant);
                onSerialConnectError(new IOException("Pairing requested: pair and connect again"));
                // pairing dialog brings app to background (onPause), but it is still partly visible (no onStop), so there is no automatic disconnect()
                break;
            case BluetoothDevice.ACTION_BOND_STATE_CHANGED:
                final int bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1);
                final int previousBondState = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, -1);
                log("bond state " + previousBondState + "->" + bondState);
                break;
            default:
                log("unknown broadcast " + intent.getAction());
                break;
        }
    }

    Future<void> _onConnectionStateChange(String deviceId, BlueConnectionState state) async {
        print('_handleConnectionChange $deviceId, $state');
        // status directly taken from gat_api.h, e.g. 133=0x85=GATT_ERROR ~= timeout
        if (state == BlueConnectionState.connected) {
            log("connect status $state, discoverServices");
            try {
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
        asdf; // Handle
        log("servicesDiscovered, status " + status);
        if (_canceled)
            return;
        _connectCharacteristics1(gatt);
    }

    void _connectCharacteristics1() {
      asdf;
        bool sync = true;
        _writePending = false;
        for (BluetoothGattService gattService in gatt.getServices()) {
            if (gattService.getUuid().equals(_BLUETOOTH_LE_CC254X_SERVICE))
                _delegate = new _Cc245XDelegate(this);
            if (gattService.getUuid().equals(_BLUETOOTH_LE_MICROCHIP_SERVICE))
                _delegate = new _MicrochipDelegate(this);
            if (gattService.getUuid().equals(_BLUETOOTH_LE_NRF_SERVICE))
                _delegate = new _NrfDelegate(this);
            if (gattService.getUuid().equals(_BLUETOOTH_LE_TIO_SERVICE))
                _delegate = new _TelitDelegate(this);

            if(_delegate != null) {
                sync = _delegate.connectCharacteristics(gattService);
                break;
            }
        }
        if(_canceled)
            return;
        if(_delegate==null || _readCharacteristic==null || _writeCharacteristic==null) {
            for (BluetoothGattService gattService in gatt.getServices()) {
                log("service "+gattService.getUuid());
                for(BluetoothGattCharacteristic characteristic in gattService.getCharacteristics())
                    log("characteristic "+characteristic.getUuid());
            }
            _onSerialConnectError(Exception("no serial profile found"));
            return;
        }
        if(sync)
            _connectCharacteristics2(gatt);
    }

    void _connectCharacteristics2() {
      asdf;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            log("request max MTU");
            if (!gatt.requestMtu(_MAX_MTU))
                _onSerialConnectError(Exception("request MTU failed"));
            // continues asynchronously in onMtuChanged
        } else {
            _connectCharacteristics3(gatt);
        }
    }

    void onMtuChanged(int mtu, int status) {
      asdf;
        log("mtu size $mtu");
        if(status ==  BluetoothGatt.GATT_SUCCESS) {
            _payloadSize = mtu - 3;
            log("payload size $_payloadSize");
        }
        _connectCharacteristics3(gatt);
    }

    void _connectCharacteristics3() {
      asdf;
        int writeProperties = _writeCharacteristic.getProperties();
        if((writeProperties & (BluetoothGattCharacteristic.PROPERTY_WRITE +     // Microbit,HM10-clone have WRITE
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE)) ==0) { // HM10,TI uart,Telit have only WRITE_NO_RESPONSE
            _onSerialConnectError(Exception("write characteristic not writable"));
            return;
        }
        if(!gatt.setCharacteristicNotification(_readCharacteristic,true)) {
            _onSerialConnectError(Exception("no notification for read characteristic"));
            return;
        }
        BluetoothGattDescriptor readDescriptor = _readCharacteristic.getDescriptor(_BLUETOOTH_LE_CCCD);
        if(readDescriptor == null) {
            _onSerialConnectError(Exception("no CCCD descriptor for read characteristic"));
            return;
        }
        int readProperties = _readCharacteristic.getProperties();
        if((readProperties & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) {
            log("enable read indication");
            readDescriptor.setValue(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE);
        }else if((readProperties & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0) {
            log("enable read notification");
            readDescriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
        } else {
            _onSerialConnectError(Exception("no indication/notification for read characteristic ($readProperties)"));
            return;
        }
        log("writing read characteristic descriptor");
        if(!gatt.writeDescriptor(readDescriptor)) {
            _onSerialConnectError(Exception("read characteristic CCCD descriptor not writable"));
        }
        // continues asynchronously in onDescriptorWrite()
    }

    void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
        delegate.onDescriptorWrite(gatt, descriptor, status);
        if(_canceled)
            return;
        if(descriptor.getCharacteristic() == _readCharacteristic) {
            log("writing read characteristic descriptor finished, status=$status");
            if (status != BluetoothGatt.GATT_SUCCESS) {
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
    void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
      asdf;
        if(_canceled)
            return;
        _delegate.onCharacteristicChanged(gatt, characteristic);
        if(_canceled)
            return;
        if(characteristic == _readCharacteristic) { // NOPMD - test object identity
            Uint8List data = _readCharacteristic.getValue();
            _onSerialRead(data);
            log("read, len=${data.length}");
        }
    }

    /*
     * write
     */
    void write(Uint8List data) throws IOException {
      asdf;
        if(_canceled || !_connected || _writeCharacteristic == null)
            throw Exception("not connected");
        Uint8List data0;
        // synchronized (writeBuffer) {
            if(data.length <= _payloadSize) {
                data0 = data;
            } else {
                data0 = Arrays.copyOfRange(data, 0, _payloadSize);
            }
            if(!_writePending && _writeBuffer.isEmpty && _delegate.canWrite()) {
                _writePending = true;
            } else {
                _writeBuffer.add(data0);
                log("write queued, len=${data0.length}");
                data0 = null;
            }
            if(data.length > _payloadSize) {
                for(int i=1; i<(data.length+_payloadSize-1)/_payloadSize; i++) {
                    int from = i*_payloadSize;
                    int to = Math.min(from+_payloadSize, data.length);
                    _writeBuffer.add(Arrays.copyOfRange(data, from, to));
                    log("write queued, len=${to-from}");
                }
            }
        // }
        if(data0 != null) {
            _writeCharacteristic.setValue(data0);
            if (!gatt.writeCharacteristic(_writeCharacteristic)) {
                _onSerialIoError(Exception("write failed"));
            } else {
                log("write started, len=${data0.length}");
            }
        }
        // continues asynchronously in onCharacteristicWrite()
    }

    void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
      asdf;
        if(_canceled || !_connected || _writeCharacteristic == null)
            return;
        if(status != BluetoothGatt.GATT_SUCCESS) {
            _onSerialIoError(Exception("write failed"));
            return;
        }
        _delegate.onCharacteristicWrite(gatt, characteristic, status);
        if(_canceled)
            return;
        if(characteristic == _writeCharacteristic) { // NOPMD - test object identity
            log("write finished, status=$status");
            _writeNext();
        }
    }

    void _writeNext() {
        final Uint8List data;
        // synchronized (writeBuffer) {
            if (!_writeBuffer.isEmpty && _delegate.canWrite()) {
                _writePending = true;
                data = _writeBuffer.removeAt(0);
            } else {
                _writePending = false;
                return;
            }
        // }
        _writeCharacteristic.setValue(data);
        if (!gatt.writeCharacteristic(_writeCharacteristic)) {
            _onSerialIoError(Exception("write failed"));
        } else {
            log("write started, len=${data.length}");
        }
    }

    /**
     * SerialListener
     */
    void _onSerialConnect() {
        if (_listener != null)
            _listener.onSerialConnect();
    }

    void _onSerialConnectError(Exception e) {
        _canceled = true;
        if (_listener != null)
            _listener.onSerialConnectError(e);
    }

    void _onSerialRead(Uint8List data) {
        if (_listener != null)
            _listener.onSerialRead(data);
    }

    void _onSerialIoError(Exception e) {
        _writePending = false;
        _canceled = true;
        if (_listener != null)
            _listener.onSerialIoError(e);
    }
}

/**
 * delegate device specific behaviour to inner class
 */
class _DeviceDelegate {
    final BleBluetoothConnection owner;

    _DeviceDelegate(this.owner);

    bool connectCharacteristics(BluetoothGattService s) { return true; }
    // following methods only overwritten for Telit devices
    void onDescriptorWrite(BluetoothGatt g, BluetoothGattDescriptor d, int status) { /*nop*/ }
    void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c) {/*nop*/ }
    void onCharacteristicWrite(BluetoothGatt g, BluetoothGattCharacteristic c, int status) { /*nop*/ }
    bool canWrite() { return true; }
    void disconnect() {/*nop*/ }
}

/**
 * device delegates
 */

class _Cc245XDelegate extends _DeviceDelegate {
    _Cc245XDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(BluetoothGattService gattService) {
        log("service cc254x uart");
        owner._readCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_CC254X_CHAR_RW);
        owner._writeCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_CC254X_CHAR_RW);
        return true;
    }
}

class _MicrochipDelegate extends _DeviceDelegate {
    _MicrochipDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(BluetoothGattService gattService) {
        log("service microchip uart");
        owner._readCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_RW);
        owner._writeCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_W);
        if(owner._writeCharacteristic == null)
            owner._writeCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_MICROCHIP_CHAR_RW);
        return true;
    }
}

class _NrfDelegate extends _DeviceDelegate {
    _NrfDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(BluetoothGattService gattService) {
        log("service nrf uart");
        BluetoothGattCharacteristic rw2 = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_NRF_CHAR_RW2);
        BluetoothGattCharacteristic rw3 = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_NRF_CHAR_RW3);
        if (rw2 != null && rw3 != null) {
            int rw2prop = rw2.getProperties();
            int rw3prop = rw3.getProperties();
            bool rw2write = (rw2prop & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0;
            bool rw3write = (rw3prop & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0;
            log("characteristic properties $rw2prop/$rw3prop");
            if (rw2write && rw3write) {
                owner._onSerialConnectError(Exception("multiple write characteristics ($rw2prop/$rw3prop)"));
            } else if (rw2write) {
                owner._writeCharacteristic = rw2;
                owner._readCharacteristic = rw3;
            } else if (rw3write) {
                owner._writeCharacteristic = rw3;
                owner._readCharacteristic = rw2;
            } else {
                owner._onSerialConnectError(Exception("no write characteristic ($rw2prop/$rw3prop)"));
            }
        }
        return true;
    }
}

class _TelitDelegate extends _DeviceDelegate {
    BluetoothGattCharacteristic _readCreditsCharacteristic, _writeCreditsCharacteristic;
    int _readCredits = 0;
    int _writeCredits = 0;

    _TelitDelegate(BleBluetoothConnection owner) : super(owner);

    @override
    bool connectCharacteristics(BluetoothGattService gattService) {
        log("service telit tio 2.0");
        _readCredits = 0;
        _writeCredits = 0;
        owner._readCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_RX);
        owner._writeCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_TX);
        _readCreditsCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_RX_CREDITS);
        _writeCreditsCharacteristic = gattService.getCharacteristic(BleBluetoothConnection._BLUETOOTH_LE_TIO_CHAR_TX_CREDITS);
        if (owner._readCharacteristic == null) {
            owner._onSerialConnectError(Exception("read characteristic not found"));
            return false;
        }
        if (owner._writeCharacteristic == null) {
            owner._onSerialConnectError(Exception("write characteristic not found"));
            return false;
        }
        if (_readCreditsCharacteristic == null) {
            owner._onSerialConnectError(Exception("read credits characteristic not found"));
            return false;
        }
        if (_writeCreditsCharacteristic == null) {
            owner._onSerialConnectError(Exception("write credits characteristic not found"));
            return false;
        }
        if (!gatt.setCharacteristicNotification(_readCreditsCharacteristic, true)) {
            owner._onSerialConnectError(Exception("no notification for read credits characteristic"));
            return false;
        }
        BluetoothGattDescriptor readCreditsDescriptor = _readCreditsCharacteristic.getDescriptor(BleBluetoothConnection._BLUETOOTH_LE_CCCD);
        if (readCreditsDescriptor == null) {
            owner._onSerialConnectError(Exception("no CCCD descriptor for read credits characteristic"));
            return false;
        }
        readCreditsDescriptor.setValue(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE);
        log("writing read credits characteristic descriptor");
        if (!gatt.writeDescriptor(readCreditsDescriptor)) {
            owner._onSerialConnectError(Exception("read credits characteristic CCCD descriptor not writable"));
            return false;
        }
        log("writing read credits characteristic descriptor");
        return false;
        // continues asynchronously in connectCharacteristics2
    }

    @override
    void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
        if(descriptor.getCharacteristic() == _readCreditsCharacteristic) {
            log("writing read credits characteristic descriptor finished, status=$status");
            if (status != BluetoothGatt.GATT_SUCCESS) {
                owner._onSerialConnectError(Exception("write credits descriptor failed"));
            } else {
                owner._connectCharacteristics2(gatt);
            }
        }
        if(descriptor.getCharacteristic() == owner._readCharacteristic) {
            log("writing read characteristic descriptor finished, status=$status");
            if (status == BluetoothGatt.GATT_SUCCESS) {
                owner._readCharacteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
                owner._writeCharacteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
                grantReadCredits();
                // grantReadCredits includes gatt.writeCharacteristic(writeCreditsCharacteristic)
                // but we do not have to wait for confirmation, as it is the last write of connect phase.
            }
        }
    }

    @override
    void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
        if(characteristic == _readCreditsCharacteristic) { // NOPMD - test object identity
            int newCredits = _readCreditsCharacteristic.getValue()[0];
            // synchronized (writeBuffer) {
                _writeCredits += newCredits;
            // }
            log("got write credits +$newCredits =$_writeCredits");

            if (!owner._writePending && owner._writeBuffer.isNotEmpty) {
                log("resume blocked write");
                owner._writeNext();
            }
        }
        if(characteristic == owner._readCharacteristic) { // NOPMD - test object identity
            grantReadCredits();
            log("read, credits=$_readCredits");
        }
    }

    @override
    void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
        if(characteristic == owner._writeCharacteristic) { // NOPMD - test object identity
            // synchronized (owner._writeBuffer) {
                if (_writeCredits > 0)
                    _writeCredits -= 1;
            // }
            log("write finished, credits=$_writeCredits");
        }
        if(characteristic == _writeCreditsCharacteristic) { // NOPMD - test object identity
            log("write credits finished, status=$status");
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

    void grantReadCredits() {
        final int minReadCredits = 16;
        final int maxReadCredits = 64;
        if(_readCredits > 0)
            _readCredits -= 1;
        if(_readCredits <= minReadCredits) {
            int newCredits = maxReadCredits - _readCredits;
            _readCredits += newCredits;
            Uint8List data = Uint8List.fromList([newCredits]);
            log("grant read credits +$newCredits =$_readCredits");
            _writeCreditsCharacteristic.setValue(data);
            if (!gatt.writeCharacteristic(_writeCreditsCharacteristic)) {
                if(owner._connected)
                    owner._onSerialIoError(Exception("write read credits failed"));
                else
                    owner._onSerialConnectError(Exception("write read credits failed"));
            }
        }
    }
}
