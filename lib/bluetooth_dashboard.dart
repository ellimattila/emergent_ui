import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:audioplayers/audioplayers.dart';

class BluetoothDashboardPage extends StatefulWidget {
  const BluetoothDashboardPage({super.key});

  @override
  State<BluetoothDashboardPage> createState() => _BluetoothDashboardPageState();
}

class _BluetoothDashboardPageState extends State<BluetoothDashboardPage> {
  final Logger logger = Logger();
  final AudioPlayer audioPlayer = AudioPlayer();

  bool exerciseStarted = false;
  int exerciseStretchCount = 0;
  final double targetForce = 5.0;
  final double minumumForce = 1.0;
  bool repCompleted = false;
  final int targetReps = 10;
  String exerciseStatus = "";

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
      final unique = <String, ScanResult>{};
      for (final r in results) {
        unique[r.device.remoteId.str] = r;
      }
      setState(() {
        devices = unique.values.toList();
      });
    });
  }

  Future<void> playRepSound() async {
    try {
      await audioPlayer.play(AssetSource('afterEachRep.mp3'));
    } catch (e) {
      logger.e("Error playing rep sound: $e");
    }
  }

  Future<void> playCompletionSound() async {
    try {
      await audioPlayer.play(AssetSource('stretchingDone.mp3'));
    } catch (e) {
      logger.e("Error playing completion sound: $e");
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      setState(() {
        connectedDevice = device;
      });

      var services = await device.discoverServices();
      for (var service in services) {
        logger.i("Service: ${service.uuid}");
        for (var characteristic in service.characteristics) {
          logger.i("  Characteristic: ${characteristic.uuid}");

          if (characteristic.properties.notify ||
              characteristic.properties.indicate) {
            logger.i(
              "[Flutter] ▶️ About to setNotifyValue on ${characteristic.uuid}",
            );
            try {
              await characteristic
                  .setNotifyValue(true)
                  .timeout(const Duration(seconds: 5));
              logger.i(
                "[Flutter] ✅ setNotifyValue succeeded on ${characteristic.uuid}",
              );
            } on TimeoutException {
              logger.i("[Flutter] ⏱️ setNotifyValue timed out!");
            } catch (e) {
              logger.i("[Flutter] ❌ setNotifyValue threw: $e");
            }

            logger.i("[Flutter] isNotifying=${characteristic.isNotifying}");

            try {
              final raw = await characteristic.read();
              final manual = utf8.decode(raw);
              logger.i(
                "[Flutter] 📖 Manual read from ${characteristic.uuid}: $manual",
              );
            } catch (e) {
              logger.i("[Flutter] ❌ Manual read failed: $e");
            }

            characteristic.lastValueStream.listen((value) async {
              final dataString = utf8.decode(value);
              logger.i('[ESP32 ➡️ Flutter] $dataString');

              if (dataString.trim() == 'stretched') {
                setState(() {
                  stretchCount++;
                  lastStretch = DateTime.now();
                });
              }

              if (!exerciseStarted) return;

              final match = RegExp(r'(\d+\.\d{2})').firstMatch(dataString);
              if (match != null) {
                final forceValue = double.tryParse(match.group(1)!);
                if (forceValue != null &&
                    forceValue >= targetForce &&
                    !repCompleted) {
                  repCompleted = true;
                  exerciseStretchCount++;
                  logger.i(
                    "✅ Detected $forceValue kg stretch ($exerciseStretchCount/$targetReps)",
                  );

                  setState(() {
                    exerciseStatus = "$exerciseStretchCount / $targetReps";
                    stretchCount++;
                    lastStretch = DateTime.now();
                  });

                  await playRepSound();

                  if (exerciseStretchCount >= targetReps) {
                    logger.i("🔔 Playing completion sound...");
                    await playCompletionSound();
                    setState(() {
                      exerciseStarted = false;
                      exerciseStretchCount = 0;
                      exerciseStatus = "✅ Done!";
                    });
                    logger.i("🎉 Exercise complete! Sound played.");
                  }
                }
                if (forceValue != null &&
                    forceValue <= minumumForce &&
                    repCompleted) {
                  repCompleted = false;
                }
              }
            });
          }

          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            writeCharacteristic = characteristic;
          }
        }
      }

      sendGreeting();
    } catch (e, stack) {
      logger.e("Bluetooth error", error: e, stackTrace: stack);
    }
  }

  void sendGreeting() async {
    if (writeCharacteristic != null) {
      try {
        await writeCharacteristic!.write(
          "Hi there! You are now connected to the App!".codeUnits,
          withoutResponse: false,
        );
        logger.i("Greeting sent!");
      } catch (e, stack) {
        logger.e("Error sending greeting", error: e, stackTrace: stack);
      }
    } else {
      logger.w("No writable characteristic found.");
    }
  }

  void resetStretchCount() {
    setState(() {
      stretchCount = 0;
      lastStretch = null;
      exerciseStarted = true;
      exerciseStretchCount = 0;
      exerciseStatus = "0 / $targetReps";
    });
    logger.i("🔁 Stretch count and exercise state reset");
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
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Settings panel coming soon...'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              resetStretchCount();
                              Navigator.pop(context);
                            },
                            child: const Text('Reset Stretch Count'),
                          ),
                        ],
                      ),
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
                        title: const Text("Last Stretching Session"),
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
                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            exerciseStarted = true;
                            exerciseStretchCount = 0;
                            exerciseStatus = "0 / $targetReps";
                          });
                          logger.i("🏁 Exercise started");
                        },
                        icon: const Icon(Icons.fitness_center),
                        label: const Text("Start stretching"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        exerciseStatus,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: deviceDisconnect,
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
