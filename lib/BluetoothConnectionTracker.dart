import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:quick_blue/quick_blue.dart';
import 'package:quiver/core.dart';

const GSS_SUFFIX = "-0000-1000-8000-00805f9b34fb";

/**
 * QuickBlue only provides a single "setConnectionHandler", for all devices.  Bleh.<br/>
 * So we can't have multiple listeners setting that.  Register your callback here.<br/>
 * <br/>
 * Don't set your own handlers on QuickBlue.  If it happens, call [resetHandlers].<br/>
 * <br/>
 * May not work right if you have multiple Isolates using QuickBlue.<br/>
 */
class BluetoothCallbackTracker { //TODO Make static instead of singleton?
    static late final INSTANCE = BluetoothCallbackTracker._();
    final WaitGroup _initialized = WaitGroup.of(1);

    final _scanSC = StreamController<BlueScanResult>();
    late final _scanStream = _scanSC.stream.asBroadcastStream();
    final Map<String, StreamController<Pair<String, List<String>>>> _serviceSCs = {};
    final Map<String, Stream<Pair<String, List<String>>>> _serviceStreams = {};
    final Map<String, StreamController<BlueConnectionState>> _connectionSCs = {};
    final Map<String, Stream<BlueConnectionState>> _connectionStreams = {};
    final Map<String, StreamController<Pair<String, Uint8List>>> _deviceValueSCs = {};
    final Map<String, Stream<Pair<String, Uint8List>>> _deviceValueStreams = {};
    final Map<Pair<String, String>, StreamController<Uint8List>> _charValueSCs = {};
    final Map<Pair<String, String>, Stream<Uint8List>> _charValueStreams = {};
    final Map<Pair<String, String>, StreamController<Pair<Uint8List, bool>>> _wroteCharSCs = {};
    final Map<Pair<String, String>, Stream<Pair<Uint8List, bool>>> _wroteCharStreams = {};

    // Some platforms demand uppercase, some demand lowercase.  Facepalm.
    static String _normalizeDevice(String s) {
        //CHECK These should probably be double-checked
        if (Platform.isWindows) {
            return s.toLowerCase();
        } else {
            return s.toUpperCase(); //CHECK This may not be right for all; Android refused lowercase
        }
    }

    static String _normalizeService(String s) {
        //CHECK These should probably be double-checked
        if (Platform.isWindows || Platform.isMacOS || Platform.isIOS || Platform.isLinux) {
            if (s.length == 4) {
                s = "0000$s$GSS_SUFFIX";
            }
            return s.toLowerCase();
        } else {
            return s.toUpperCase(); //DITTO
        }
    }

    void _ensureServiceScan(String deviceId) {
        deviceId = _normalizeDevice(deviceId);
        if (!_serviceSCs.containsKey(deviceId)) {
            final sc = StreamController<Pair<String, List<String>>>();
            _serviceSCs[deviceId] = sc;
            final s = sc.stream.asBroadcastStream();
            s.listen((m) {});
            _serviceStreams[deviceId] = s;
        }
    }

    void _ensureConnection(String deviceId) {
        deviceId = _normalizeDevice(deviceId);
        if (!_connectionSCs.containsKey(deviceId)) {
            final sc = StreamController<BlueConnectionState>();
            _connectionSCs[deviceId] = sc;
            final s = sc.stream.asBroadcastStream();
            s.listen((m) {});
            _connectionStreams[deviceId] = s;
        }
    }

    void _ensureDeviceValue(String deviceId) {
        deviceId = _normalizeDevice(deviceId);
        if (!_deviceValueSCs.containsKey(deviceId)) {
            final sc = StreamController<Pair<String, Uint8List>>();
            _deviceValueSCs[deviceId] = sc;
            final s = sc.stream.asBroadcastStream();
            s.listen((m) {});
            _deviceValueStreams[deviceId] = s;
        }
    }

    void _ensureCharValue(String deviceId, String characteristicId) {
        deviceId = _normalizeDevice(deviceId);
        characteristicId = _normalizeService(characteristicId);
        final p = Pair(deviceId, characteristicId);
        if (!_charValueSCs.containsKey(p)) {
            final sc = StreamController<Uint8List>();
            _charValueSCs[p] = sc;
            final s = sc.stream.asBroadcastStream();
            s.listen((m) {});
            _charValueStreams[p] = s;
        }
    }

    void _ensureWroteChar(String deviceId, String characteristicId) {
        deviceId = _normalizeDevice(deviceId);
        characteristicId = _normalizeService(characteristicId);
        final p = Pair(deviceId, characteristicId);
        if (!_wroteCharSCs.containsKey(p)) {
            final sc = StreamController<Pair<Uint8List, bool>>();
            _wroteCharSCs[p] = sc;
            final s = sc.stream.asBroadcastStream();
            s.listen((m) {});
            _wroteCharStreams[p] = s;
        }
    }

    Stream<BlueScanResult> subscribeForScanResults() {
        return _scanStream;
    }

    Stream<Pair<String, List<String>>> subscribeForServiceResults(String deviceId) {
        deviceId = _normalizeDevice(deviceId);
        _ensureServiceScan(deviceId);
        return _serviceStreams[deviceId]!;
    }

    Stream<BlueConnectionState> subscribeForConnectionResults(String deviceId) {
        deviceId = _normalizeDevice(deviceId);
        _ensureConnection(deviceId);
        return _connectionStreams[deviceId]!;
    }

    /**
     * Subscribe to any (characteristicId, data) coming in for a given deviceId.<br/>
     */
    Stream<Pair<String, Uint8List>> subscribeForDeviceValues(String deviceId) {
        deviceId = _normalizeDevice(deviceId);
        // log("Adding subscription for $deviceId");
        _ensureDeviceValue(deviceId);
        return _deviceValueStreams[deviceId]!;
    }

    /**
     * Subscribe to any data coming in for a given deviceId and characteristicId.<br/>
     */ //DUMMY Should probably support same chars on different services
    Stream<Uint8List> subscribeForCharacteristicValues(String deviceId, String characteristicId) {
        deviceId = _normalizeDevice(deviceId);
        characteristicId = _normalizeService(characteristicId);
        _ensureCharValue(deviceId, characteristicId);
        return _charValueStreams[Pair(deviceId, characteristicId)]!;
    }

    /**
     * Subscribe to notifications of success of outgoing writes to characteristics.<br/>
     * Stream is of characteristic `value` (exactly what that means may depend on platform, not sure) and `success`.<br/>
     */ //DUMMY Should probably support same chars on different services
    Stream<Pair<Uint8List, bool>> subscribeForWroteCharacteristic(String deviceId, String characteristicId) {
        deviceId = _normalizeDevice(deviceId);
        characteristicId = _normalizeService(characteristicId);
        _ensureWroteChar(deviceId, characteristicId);
        return _wroteCharStreams[Pair(deviceId, characteristicId)]!;
    }

    Set<Token> _scanTokens = {};
    Future<Token> startScan() async {
        await _initialized.wait();
        if (_scanTokens.isEmpty) {
            await QuickBlue.startScan();
        }
        var t = Token();
        _scanTokens.add(t);
        return t;
    }
    Future<void> stopScan(Token t) async {
        await _initialized.wait();
        _scanTokens.remove(t);
        if (_scanTokens.isEmpty) {
            await QuickBlue.stopScan();
        }
    }
    bool isScanning() {
        return _scanTokens.isNotEmpty;
    }

    Future<bool> isBluetoothAvailable() async {
        await _initialized.wait();
        return await QuickBlue.isBluetoothAvailable();
    }

    //DUMMY Many of these things will, occasionally, deadlock.  Deal with it somehow.
    //TODO These should be merged with the "subscribe" functions, frankly; they're here because of the way this grew into existence
    Future<void> connect(String deviceId) async {
        deviceId = _normalizeDevice(deviceId);
        await _initialized.wait();
        return QuickBlue.connect(deviceId);
    }
    Future<void> discoverServices(String deviceId) async {
        deviceId = _normalizeDevice(deviceId);
        await _initialized.wait();
        return QuickBlue.discoverServices(deviceId);
    }
    Future<void> setNotifiable(String deviceId, String service, String characteristic, BleInputProperty bleInputProperty) async {
        await _initialized.wait();
        deviceId = _normalizeDevice(deviceId);
        service = _normalizeService(service);
        characteristic = _normalizeService(characteristic);
        return QuickBlue.setNotifiable(deviceId, service, characteristic, bleInputProperty);
    }
    Future<void> disconnect(String deviceId) async {
        await _initialized.wait();
        deviceId = _normalizeDevice(deviceId);
        return QuickBlue.disconnect(deviceId);
    }

    /**
     * Note that this just subscribes for one value, then requests a value.
     * It's possible it will return a value not triggered by the read - but that shouldn't matter for normal cases.
     * Note also that anything subscribed to the characteristic will get the value, too.
     */
    Future<Uint8List> readValue(String deviceId, String service, String characteristic) async { //CHECK This deadlocks sometimes.  Timeout all occurrences?
        await _initialized.wait();
        deviceId = _normalizeDevice(deviceId);
        service = _normalizeService(service);
        characteristic = _normalizeService(characteristic);
        Future<Uint8List> fVal = subscribeForCharacteristicValues(deviceId, characteristic).first;
        await QuickBlue.readValue(deviceId, service, characteristic);
        return await fVal;
    }
    Future<void> writeValue(String deviceId, String service, String characteristic, Uint8List data) async {
        await _initialized.wait();
        deviceId = _normalizeDevice(deviceId);
        service = _normalizeService(service);
        characteristic = _normalizeService(characteristic);
        return QuickBlue.writeValue(deviceId, service, characteristic, data, BleOutputProperty.withResponse); // On Mac, this doesn't work withoutResponse ... Ok, it's no longer working WITH it.  :|
    }


    BluetoothCallbackTracker._() {
        // log("--> BluetoothCallbackTracker init");
        _scanStream.listen((x) {});

        unawaited(Future(() async {
            QuickBlue.scanResultStream.listen(_handleScanResult);
            _initialized.done();
        }));

        resetHandlers();
        // log("<-- BluetoothCallbackTracker init");
    }

    void resetHandlers() {
        QuickBlue.setServiceHandler(_handleServiceDiscovery);
        QuickBlue.setConnectionHandler(_handleConnectionChange);
        QuickBlue.setValueHandler(_handleValueChange);
        QuickBlue.setOnWroteCharateristicHandler(_handleWroteChar);
    }

    void _handleScanResult(BlueScanResult result) {
        result.deviceId = _normalizeDevice(result.deviceId); // This is DUMB
        // log('onScanResult ${result.rssi} ${result.deviceId} ${result.name}');
        _scanSC.add(result);
    }

    void _handleServiceDiscovery(String deviceId, String serviceId, List<String> characteristicIds) {
        deviceId = _normalizeDevice(deviceId);
        serviceId = _normalizeService(serviceId);
        for (int i = 0; i < characteristicIds.length; i++) {
            characteristicIds[i] = _normalizeService(characteristicIds[i]);
        }
        // log('_handleServiceDiscovery $deviceId, $serviceId, $characteristicIds');
        _ensureServiceScan(deviceId);
        _serviceSCs[deviceId]!.add(Pair(serviceId, characteristicIds));
    }

    void _handleConnectionChange(String deviceId, BlueConnectionState state) {
        deviceId = _normalizeDevice(deviceId);
        log("_handleConnectionChange $deviceId, ${state.value}");
        _ensureConnection(deviceId);
        _connectionSCs[deviceId]!.add(state);
    }

    void _handleValueChange(String deviceId, String characteristicId, Uint8List value) {
        deviceId = _normalizeDevice(deviceId);
        characteristicId = _normalizeService(characteristicId);
        // log('_handleValueChange $deviceId, $characteristicId, ${value}');
        _ensureCharValue(deviceId, characteristicId);
        _charValueSCs[Pair(deviceId, characteristicId)]!.add(value);
        _ensureDeviceValue(deviceId);
        _deviceValueSCs[deviceId]!.add(Pair(characteristicId, value));
    }

    void _handleWroteChar(String deviceId, String characteristicId, Uint8List value, bool success) {
        log("_handleWroteChar $deviceId $characteristicId $success");
        deviceId = _normalizeDevice(deviceId);
        characteristicId = _normalizeService(characteristicId);
        // log('_handleWroteChar $deviceId, $characteristicId, ${value}, $success');
        _ensureWroteChar(deviceId, characteristicId);
        _wroteCharSCs[Pair(deviceId, characteristicId)]!.add(Pair(value, success));
    }
}

class Pair<A, B> {
    final A a;
    final B b;

    const Pair(this.a, this.b);

    @override
    bool operator ==(Object other) {
        if (!(other is Pair<A, B>)) {
            return false;
        }
        return (a == other.a && b == other.b);
    }

    @override
    int get hashCode => hash2(a, b);

    @override
    String toString() {
        return "($a,$b)";
    }
}

class Token {
}

class WaitGroup {
    var _c = Completer<void>();
    var _i = 0;

    WaitGroup();

    WaitGroup.of(int count): _i = count;

    void add(int j) {
        _i += j;
    }

    void done() {
        _i--;
        if (_i == 0) {
            _c.complete(null);
            _c = Completer<void>();
        }
    }

    Future<void> wait() async {
        if (_i > 0) {
            return _c.future;
        }
    }
}

bool uuidsEqual(String? a, String? b) {
    if (a == b) {
        return true;
    }
    if (a == null || b == null) {
        return false;
    }
    return BluetoothCallbackTracker._normalizeService(a) == BluetoothCallbackTracker._normalizeService(b);
}