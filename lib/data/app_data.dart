// app_data.dart - Touchmatik Glide V1.1.0 (Agragamee, Oct-2026): the one configuration the app edits.
// V1.1.0: boardType (header byte 3, set by Generate and Process) and panelNo (the one panel number,
// from the Panel page). checkConfig's results are configErrors / configWarnings in config_check.dart.
import 'dart:convert';
import '../services/hex_tools.dart';

class AppDataManager {
  static final AppDataManager _instance = AppDataManager._internal();
  factory AppDataManager() => _instance;
  AppDataManager._internal();

  // Customer Info
  String? customerName;
  String? customerAddress;
  String? selectedFile;
  bool selectedFileFromCustomerInfo = false;
  bool alreadyHaveHexSelected = false;

  // Panel Switch Assign
  String? panelSwitchPanel;
  String? panelSwitchLocation;
  String? panelSwitchModule;
  List<Map<String, dynamic>> panelSwitchRows = [];

  // Relay Output
  List<Map<String, dynamic>> relayOutputRows = [];

  // Input Assign
  String? inputAssignPanel;
  List<Map<String, dynamic>> inputAssignRows = [];


  // Scene Assign
  List<Map<String, dynamic>> sceneAssignRows = [];

  // Connectivity
  int connectivityType = 0; // 0: Modbus, 1: WiFi/BLE

  // Modbus Settings
  String? modbusComPort; // New: To store the selected COM port
  String? modbusBaudRate;
  String? modbusDataBit;
  String? modbusStopBit;
  String? modbusParity;
  bool isBroadcast = false;
  String? panelNumber;

  // WiFi/BLE Settings
  String? wifiPanel;
  String? wifiMode;

  // MQTT Settings
  String? mqttBroker;
  String? mqttPort;
  String? mqttUser;
  String? mqttPassword;
  List<Map<String, dynamic>> mqttDevices = [];

  // Tuya Settings
  String? tuyaPid;
  List<Map<String, dynamic>> tuyaDevices = [];

  // V1.1.0: header board type of generated files: 'STANDALONE' (default) or 'RCU'
  String boardType = 'STANDALONE';

  // V1.1.0 (C2): the one panel number 1..48, from the Panel page ('Panel-05' -> 5); null = not chosen
  int? get panelNo => panelNumberOf(panelSwitchPanel);

  void fromFileContent(String content) {
    final lines = content.split('\n');
    for (var line in lines) {
      final parts = line.split(': ');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join(': ').trim();
        switch (key) {
          case 'Name':
            customerName = value;
            break;
          case 'Address':
            customerAddress = value;
            break;
          case 'File':
            selectedFile = value;
            break;
          case 'PanelSwitchPanel':
            panelSwitchPanel = value;
            break;
          case 'PanelSwitchLocation':
            panelSwitchLocation = value;
            break;
          case 'PanelSwitchModule':
            panelSwitchModule = value;
            break;
          case 'PanelSwitchRows':
            panelSwitchRows = List<Map<String, dynamic>>.from(jsonDecode(value));
            break;
          case 'RelayOutputRows':
            relayOutputRows = List<Map<String, dynamic>>.from(jsonDecode(value));
            break;
          case 'InputAssignPanel':
            inputAssignPanel = value;
            break;
          case 'InputAssignRows':
            inputAssignRows = List<Map<String, dynamic>>.from(jsonDecode(value));
            break;
          case 'SceneAssignRows':
            sceneAssignRows = List<Map<String, dynamic>>.from(jsonDecode(value));
            break;
          case 'ConnectivityType':
            connectivityType = int.tryParse(value) ?? 0;
            break;
          case 'ModbusComPort':
            modbusComPort = value;
            break;
          case 'ModbusBaudRate':
            modbusBaudRate = value;
            break;
          case 'ModbusDataBit':
            modbusDataBit = value;
            break;
          case 'ModbusStopBit':
            modbusStopBit = value;
            break;
          case 'ModbusParity':
            modbusParity = value;
            break;
          case 'IsBroadcast':
            isBroadcast = value.toLowerCase() == 'true';
            break;
          case 'PanelNumber':
            panelNumber = value;
            break;
          case 'WifiPanel':
            wifiPanel = value;
            break;
          case 'WifiMode':
            wifiMode = value;
            break;
          case 'MqttBroker':
            mqttBroker = value;
            break;
          case 'MqttPort':
            mqttPort = value;
            break;
          case 'MqttUser':
            mqttUser = value;
            break;
          case 'MqttPassword':
            mqttPassword = value;
            break;
          case 'MqttDevices':
            mqttDevices = List<Map<String, dynamic>>.from(jsonDecode(value));
            break;
          case 'TuyaPid':
            tuyaPid = value;
            break;
          case 'TuyaDevices':
            tuyaDevices = List<Map<String, dynamic>>.from(jsonDecode(value));
            break;
        }
      }
    }
  }

  void clear() {
    customerName = null;
    customerAddress = null;
    selectedFile = null;
    panelSwitchPanel = null;
    panelSwitchLocation = null;
    panelSwitchModule = null;
    panelSwitchRows = [];
    relayOutputRows = [];
    inputAssignPanel = null;
    inputAssignRows = [];
    sceneAssignRows = [];
    connectivityType = 0;
    modbusComPort = null;
    modbusBaudRate = null;
    modbusDataBit = null;
    modbusStopBit = null;
    modbusParity = null;
    isBroadcast = false;
    panelNumber = null;
    wifiPanel = null;
    wifiMode = null;
    mqttBroker = null;
    mqttPort = null;
    mqttUser = null;
    mqttPassword = null;
    mqttDevices = [];
    tuyaPid = null;
    tuyaDevices = [];
    boardType = 'STANDALONE';
  }
}
