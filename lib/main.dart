import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'firebase_options.dart'; // Wygenerowany przez flutterfire configure

final logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moja Aplikacja',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          User? user = snapshot.data;
          if (user != null && user.emailVerified) {
            return const ProductListPage();
          } else {
            return const LoginScreen();
          }
        }
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Wypełnij wszystkie pola.');
      return;
    }
    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (!userCredential.user!.emailVerified) {
        await userCredential.user!.sendEmailVerification();
        setState(() {
          _errorMessage = 'Proszę zweryfikować email. Wysłano link weryfikacyjny.';
        });
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Błąd logowania: ${e.toString()}';
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logowanie')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Hasło'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _signIn,
              child: const Text('Zaloguj się'),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class Produkt {
  final String nazwa;
  final String kod;
  final double stan;

  Produkt({required this.nazwa, required this.kod, required this.stan});
}

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  final List<List<dynamic>> _products = [];
  final List<List<dynamic>> _filteredProducts = [];
  bool _isLoading = true;
  bool _sortAscending = true;
  int _sortColumnIndex = 3; // Sortowanie po kolumnie Cennik
  String _searchQuery = '';
  String? _selectedCennik;
  final List<String> _cennikOptions = [];
  String? _errorMessage;

  final String csvUrl =
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vRIATYDK0VLRsdhiwcDSl85TQZNsWPzeT7ap4S89dPyh-X_xZtBFy9ASEGXCbbsZrEGQeahN-66VpDX/pub?output=csv';

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _fetchCsvData();
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString('cached_products');
    if (cachedData != null) {
      final csvBody = const CsvToListConverter().convert(cachedData);
      _processCsvData(csvBody);
    }
  }

  Future<void> _fetchCsvData({int limit = 100}) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(csvUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Przekroczono czas oczekiwania na odpowiedź serwera'),
      );
      if (response.statusCode == 200) {
        final csvBody = const CsvToListConverter().convert(utf8.decode(response.bodyBytes))
            .sublist(1)
            .take(limit)
            .toList();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_products', response.body);
        _processCsvData(csvBody);
      } else {
        throw Exception('Błąd pobierania danych: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Błąd: ${e.toString()}';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processCsvData(List<List<dynamic>> csvBody) {
    if (mounted) {
      setState(() {
        _products.clear();
        _products.addAll(csvBody);
        _filteredProducts.clear();
        _filteredProducts.addAll(_products);
        _cennikOptions.clear();
        _cennikOptions.addAll(_products.map((p) => p[3]?.toString() ?? '').toSet());
        _sortProducts(_sortColumnIndex);
        _applyFiltersAndSearch();
      });
    }
  }

  void _sortProducts(int columnIndex) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _filteredProducts.sort((a, b) {
        final valueA = a[columnIndex]?.toString() ?? '';
        final valueB = b[columnIndex]?.toString() ?? '';
        return _sortAscending ? valueA.compareTo(valueB) : valueB.compareTo(valueA);
      });
    });
  }

  void _applyFiltersAndSearch() {
    setState(() {
      _filteredProducts.clear();
      _filteredProducts.addAll(_products.where((product) {
        final matchesCennik = _selectedCennik == null || product[3]?.toString() == _selectedCennik;
        final matchesSearch = _searchQuery.isEmpty ||
            (product[1]?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
            (product[3]?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
        return matchesCennik && matchesSearch;
      }));
      _sortProducts(_sortColumnIndex);
    });
  }

  void zamowProdukt(BuildContext context, Produkt produkt) async {
    final controller = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zaloguj się, aby złożyć zamówienie.')));
      return;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Zamów: ${produkt.nazwa}'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Ilość (max: ${produkt.stan.toStringAsFixed(2)} m²)'),
            onChanged: (value) => setDialogState(() {}),
          ),
          actions: [
            TextButton(
              child: const Text('Anuluj'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Zamów'),
              onPressed: () async {
                final ilosc = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
                if (ilosc <= 0 || ilosc > produkt.stan) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nieprawidłowa ilość.')));
                  }
                  return;
                }

                final now = DateTime.now();
                final login = user.email!.split('@').first;
                final fileName = 'zamowienie_${login}_${now.toIso8601String().replaceAll(':', '-')}.csv';

                final rows = [
                  ['Kod', 'Ilość (m²)'],
                  [produkt.kod, ilosc.toStringAsFixed(2).replaceAll('.', ',')],
                ];

                final csvData = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
                final directory = await getApplicationDocumentsDirectory();
                final path = '${directory.path}/$fileName';
                final file = File(path);
                await file.writeAsString(csvData);

                await sendEmailWithAttachment(
                  recipient: 'biuro@twojafirma.pl',
                  subject: 'Zamówienie od $login',
                  body: 'W załączniku znajduje się plik z zamówieniem z dnia ${now.toLocal().toString().split('.')[0]}.',
                  attachmentPath: path,
                  onSuccess: () {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zamówienie wysłane!')));
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  onError: () {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Błąd wysyłania zamówienia.')));
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> sendEmailWithAttachment({
    required String recipient,
    required String subject,
    required String body,
    required String attachmentPath,
    required VoidCallback onSuccess,
    required VoidCallback onError,
  }) async {
    const username = 'paulina.jarmuzek.fachowiec@gmail.com';
    const password = 'upvmohztwbdnflhp'; // Zastąp hasłem aplikacji Gmail
    final smtpServer = gmail(username, password);

    final message = Message()
      ..from = Address(username, 'Twoja Apka')
      ..recipients.add(recipient)
      ..subject = subject
      ..text = body
      ..attachments.add(FileAttachment(File(attachmentPath)));

    try {
      final sendReport = await send(message, smtpServer);
      logger.i('Wysłano: $sendReport');
      onSuccess();
    } catch (e) {
      logger.e('Błąd przy wysyłaniu e-maila: $e');
      onError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista Produktów'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('cached_products');
              if (mounted) setState(() {});
            },
            tooltip: 'Wyloguj się',
          ),
          IconButton(
            icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
            onPressed: () {
              setState(() {
                _sortAscending = !_sortAscending;
                _sortProducts(_sortColumnIndex);
              });
            },
            tooltip: 'Zmień kierunek sortowania',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchCsvData,
        tooltip: 'Odśwież dane',
        child: const Icon(Icons.refresh),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Wyszukaj (Nazwa lub Cennik)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                _searchQuery = value;
                _applyFiltersAndSearch();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButton<String>(
              hint: const Text('Wybierz Cennik'),
              value: _selectedCennik,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Wszystkie'),
                ),
                ..._cennikOptions.map((cennik) => DropdownMenuItem<String>(
                      value: cennik,
                      child: Text(cennik),
                    )),
              ],
              onChanged: (value) {
                _selectedCennik = value;
                _applyFiltersAndSearch();
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : _filteredProducts.isEmpty
                        ? const Center(child: Text('Brak produktów do wyświetlenia'))
                        : ListView.separated(
                            itemCount: _filteredProducts.length,
                            separatorBuilder: (context, index) => const Divider(),
                            itemBuilder: (context, index) {
                              final product = _filteredProducts[index];
                              final stockString = product[5]?.toString() ?? '0';
                              final stock = double.tryParse(stockString.replaceAll(',', '.')) ?? 0;
                              if (stock.isNaN) {
                                logger.w('Błąd parsowania stock dla produktu ${product[1]}');
                              }
                              final produkt = Produkt(
                                nazwa: product[1]?.toString() ?? 'Brak nazwy',
                                kod: product[2]?.toString() ?? '',
                                stan: stock,
                              );
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: ListTile(
                                  title: Text(
                                    produkt.nazwa,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text('Kod: ${produkt.kod} | Cennik: ${product[3]}'),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'ID: ${product[0]}',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        stock > 0 ? 'Stan: ${produkt.stan.toStringAsFixed(2)} m²' : 'Chwilowo brak',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => zamowProdukt(context, produkt),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}