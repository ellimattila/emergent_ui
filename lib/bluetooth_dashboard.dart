import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothDashboardPage extends StatefulWidget {
  const BluetoothDashboardPage({super.key});

  @override
  State<BluetoothDashboardPage> createState() => _BluetoothDashboardPageState();
}

class _BluetoothDashboardPageState extends State<BluetoothDashboardPage> {
  List<ScanResult> devices = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? notifyCharacteristic;
  BluetoothCharacteristic? writeCharacteristic;

  int stretchCount = 0;
  DateTime? lastStretch;
  int dailyGoal = 5;
  int streak = 4;

  void startScan() async {
    await FlutterBluePlus.stopScan();
    devices.clear();
    setState(() {});
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    FlutterBluePlus.scanResults.listen((results) {
      // Filter duplicates by device ID
      final unique = <String, ScanResult>{};
      for (final r in results) {
        unique[r.device.remoteId.str] = r;
      }
      setState(() {
        devices = unique.values.toList();
      });
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      setState(() {
        connectedDevice = device;
      });

      var services = await device.discoverServices();
      for (var service in services) {
        print("Service: ${service.uuid}");
        for (var characteristic in service.characteristics) {
          print("  Characteristic: ${characteristic.uuid}");

          if (characteristic.properties.notify ||
              characteristic.properties.indicate) {
            await characteristic.setNotifyValue(true);
            notifyCharacteristic = characteristic;

            characteristic.lastValueStream.listen((value) {
              final dataString = String.fromCharCodes(value);
              print("Arduino sent: $dataString");

              if (dataString.trim() == "stretched") {
                setState(() {
                  stretchCount++;
                  lastStretch = DateTime.now();
                });
              }
            });
          }

          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            writeCharacteristic = characteristic;
          }
        }
      }

      // Send greeting automatically after connecting
      sendGreeting();
    } catch (e) {
      print("Bluetooth error: $e");
    }
  }

  void sendGreeting() async {
    if (writeCharacteristic != null) {
      try {
        await writeCharacteristic!.write(
          "Hi there! You are now connected to the App!".codeUnits,
          withoutResponse: true,
        );
        print("Greeting sent!");
      } catch (e) {
        print("Error sending greeting: $e");
      }
    } else {
      print("No writable characteristic found.");
    }
  }

  void deviceDisconnect() {
    connectedDevice?.disconnect();
    setState(() {
      connectedDevice = null;
      notifyCharacteristic = null;
      writeCharacteristic = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final percent = (stretchCount / dailyGoal).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Stretch Tracker"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('Settings'),
                      content: const Text('Settings panel coming soon...'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
              );
            },
          ),
        ],
      ),
      body:
          connectedDevice == null
              ? Column(
                children: [
                  ElevatedButton(
                    onPressed: startScan,
                    child: const Text("Scan for Devices"),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final result = devices[index];
                        final device = result.device;
                        final name = result.advertisementData.advName;

                        return ListTile(
                          title: Text(
                            name.isNotEmpty ? name : device.remoteId.toString(),
                          ),
                          subtitle: Text("RSSI: ${result.rssi}"),
                          onTap: () => connectToDevice(device),
                        );
                      },
                    ),
                  ),
                ],
              )
              : Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Today's Progress",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: percent,
                              minHeight: 12,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            const SizedBox(height: 8),
                            Text("$stretchCount / $dailyGoal stretches"),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text("Last Stretch"),
                        subtitle: Text(
                          lastStretch != null
                              ? "${lastStretch!.hour}:${lastStretch!.minute.toString().padLeft(2, '0')} today"
                              : "No stretch yet",
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.local_fire_department,
                          color: Colors.orange,
                        ),
                        title: const Text("Streak"),
                        subtitle: Text("$streak days in a row!"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: sendGreeting,
                        icon: const Icon(Icons.send),
                        label: const Text("Send Greeting"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          deviceDisconnect();
                        },
                        icon: const Icon(Icons.link_off),
                        label: const Text("Disconnect"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
