import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart'; // Wygenerowany przez flutterfire configure

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

// Warstwa sprawdzająca stan logowania
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData) {
          User? user = snapshot.data;
          if (user != null && user.emailVerified) {
            return const ProductListPage(); // Kieruje do listy produktów po zalogowaniu
          } else {
            return const LoginScreen();
          }
        }
        return const LoginScreen();
      },
    );
  }
}

// Ekran logowania
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  Future<void> _signIn() async {
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

// Ekran listy produktów
class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  List<List<dynamic>> _products = [];
  List<List<dynamic>> _filteredProducts = [];
  bool _isLoading = false;
  bool _sortAscending = true;
  int _sortColumnIndex = 3; // Sortowanie po kolumnie Cennik
  String _searchQuery = '';
  String? _selectedCennik;
  List<String> _cennikOptions = [];
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
      setState(() {
        _products = List.from(csvBody.sublist(1));
        _filteredProducts = List.from(_products);
        _cennikOptions = _products.map((p) => p[3].toString()).toSet().toList();
        _sortProducts(_sortColumnIndex);
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchCsvData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse(csvUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Przekroczono czas oczekiwania na odpowiedź serwera');
        },
      );

      if (response.statusCode == 200) {
        final csvBody = const CsvToListConverter().convert(
          utf8.decode(response.bodyBytes),
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_products', response.body);

        setState(() {
          _products = List.from(csvBody.sublist(1));
          _filteredProducts = List.from(_products);
          _cennikOptions = _products.map((p) => p[3].toString()).toSet().toList();
          _sortProducts(_sortColumnIndex);
          _applyFiltersAndSearch();
          _isLoading = false;
        });
      } else {
        throw Exception('Błąd pobierania danych: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Błąd: ${e.toString()}';
      });
    }
  }

  void _sortProducts(int columnIndex) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _filteredProducts.sort((a, b) {
        final valueA = a[columnIndex].toString();
        final valueB = b[columnIndex].toString();
        return _sortAscending
            ? valueA.compareTo(valueB)
            : valueB.compareTo(valueA);
      });
    });
  }

  void _applyFiltersAndSearch() {
    setState(() {
      _filteredProducts = _products.where((product) {
        final matchesCennik = _selectedCennik == null || product[3] == _selectedCennik;
        final matchesSearch = _searchQuery.isEmpty ||
            product[1].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            product[3].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        return matchesCennik && matchesSearch;
      }).toList();
      _sortProducts(_sortColumnIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista Produktów'),
        actions: [
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
                        : ListView.builder(
                            itemCount: _filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = _filteredProducts[index];
                              final stockString = product[5]?.toString() ?? '0';
                              final stock = double.tryParse(stockString.replaceAll(',', '.')) ?? 0;
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: ListTile(
                                  title: Text(
                                    product[1].toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text('Kod: ${product[2]} | Cennik: ${product[3]}'),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'ID: ${product[0]}',
                                        style: TextStyle(
                                          color: Colors.green[800],
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        stock > 0 ? 'Stan: ${product[5]} m²' : 'Chwilowo brak',
                                        style: TextStyle(
                                          color: Colors.green[800],
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
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