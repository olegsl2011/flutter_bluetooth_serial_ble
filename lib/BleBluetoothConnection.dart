import 'dart:typed_data';

import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:quick_blue/quick_blue.dart';

class BleBluetoothConnection implements BluetoothConnection {
  @override
  Stream<Uint8List>? input;

  @override
  var output;

  final String address;

  BleBluetoothConnection(this.address) {
    void _handleConnectionChange(String deviceId, BlueConnectionState state) {
      print('_handleConnectionChange $deviceId, $state');
    }

    QuickBlue.setConnectionHandler(_handleConnectionChange);

    QuickBlue.connect(address);
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
}