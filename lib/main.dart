import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class Product {
  final String code, name, priceList;
  final double quantity;
  Product({
    required this.code,
    required this.name,
    required this.priceList,
    required this.quantity,
  });
}

class CartItem {
  final Product product;
  double quantity;
  CartItem({required this.product, required this.quantity});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aplikacja Produktowa',
      theme: ThemeData(primarySwatch: Colors.purple),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasData && snap.data!.emailVerified) {
          return const ProductListPage();
        }
        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;
  String error = '';

  Future<void> login() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final res = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );
      if (!res.user!.emailVerified) {
        await res.user!.sendEmailVerification();
        error = 'Potwierdź email – wysłano link.';
        await FirebaseAuth.instance.signOut();
      }
    } on FirebaseAuthException catch (e) {
      error = e.message ?? 'Błąd logowania';
    } catch (_) {
      error = 'Nieoczekiwany błąd.';
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logowanie')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Hasło'),
            ),
            const SizedBox(height: 24),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(error, style: const TextStyle(color: Colors.red)),
              ),
            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: login,
                    child: const Text('Zaloguj się'),
                  ),
          ],
        ),
      ),
    );
  }
}

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});
  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage>
    with WidgetsBindingObserver {
  final List<Product> products = [];
  List<Product> filtered = [];
  final List<CartItem> cart = [];
  bool loading = true, sending = false;
  String? errorMsg;
  final searchCtrl = TextEditingController();

  // Filtrowanie po cenniku
  List<String> priceLists = const [];
  String selectedPriceList = 'Wszystkie';

  // Auto-wylogowanie
  static const Duration kInactivityTimeout = Duration(minutes: 5);
  Timer? _idleTimer;

  final csvUrl =
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vRIATYDK0VLRsdhiwcDSl85TQZNsWPzeT7ap4S89dPyh-X_xZtBFy9ASEGXCbbsZrEGQeahN-66VpDX/pub?output=csv';

  @override
  void initState() {
    super.initState();
    fetchProducts();
    searchCtrl.addListener(() {
      filterProducts();
      _resetIdleTimer();
    });
    WidgetsBinding.instance.addObserver(this);
    _startIdleTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _cancelIdleTimer();
    } else if (state == AppLifecycleState.resumed) {
      _startIdleTimer();
    }
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    _cancelIdleTimer();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ====== AUTOLOGOUT ======
  void _startIdleTimer() {
    _cancelIdleTimer();
    _idleTimer = Timer(kInactivityTimeout, _onIdleTimeout);
  }

  void _resetIdleTimer() {
    if (!mounted) return;
    _startIdleTimer();
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  Future<void> _onIdleTimeout() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Brak aktywności – nastąpiło wylogowanie'),
        ),
      );
    }
    await FirebaseAuth.instance.signOut();
  }

  // ====== DANE ======
  Future<void> fetchProducts() async {
    setState(() {
      loading = true;
      errorMsg = null;
    });
    try {
      final resp = await http.get(Uri.parse(csvUrl));
      if (resp.statusCode != 200) throw 'HTTP ${resp.statusCode}';
      final str = utf8.decode(resp.bodyBytes);
      final rows = const CsvToListConverter().convert(str);

      products.clear();
      for (var row in rows.skip(1)) {
        final qStr = row[5]?.toString().replaceAll(',', '.') ?? '0';
        products.add(
          Product(
            code: row[0]?.toString() ?? '',
            name: row[1]?.toString() ?? '',
            priceList: row[3]?.toString() ?? '',
            quantity: double.tryParse(qStr) ?? 0,
          ),
        );
      }

      // zbuduj listę cenników
      final setPL = <String>{};
      for (final p in products) {
        if (p.priceList.trim().isNotEmpty) setPL.add(p.priceList.trim());
      }
      final lists = setPL.toList()..sort();
      priceLists = ['Wszystkie', ...lists];

      filterProducts();
    } catch (e) {
      errorMsg = e.toString();
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  void filterProducts() {
    final q = searchCtrl.text.toLowerCase().trim();
    final byText = products.where(
      (p) =>
          p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q),
    );

    List<Product> byList;
    if (selectedPriceList == 'Wszystkie') {
      byList = byText.toList();
    } else {
      byList = byText
          .where((p) => p.priceList.trim() == selectedPriceList)
          .toList();
    }

    setState(() => filtered = byList);
  }

  void addToCart(Product p) {
    _resetIdleTimer();
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Zamów: ${p.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Ilość (max ${p.quantity})'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
              if (val > 0 && val <= p.quantity) {
                setState(() {
                  final idx = cart.indexWhere((c) => c.product.code == p.code);
                  if (idx >= 0) {
                    final newQty = cart[idx].quantity + val;
                    if (newQty <= p.quantity) {
                      cart[idx].quantity = newQty;
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Maksymalnie ${p.quantity.toStringAsFixed(2)}',
                          ),
                        ),
                      );
                    }
                  } else {
                    cart.add(CartItem(product: p, quantity: val));
                  }
                });
                Navigator.pop(context);
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Dodano ${p.name}')));
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Niepoprawna ilość')),
                );
              }
            },
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );
  }

  // ====== PODGLĄD KOSZYKA (edycja, usuwanie, podgląd CSV) ======
  void showCartPreview() {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Koszyk jest pusty')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final totalLines = cart.length;
            final totalQty = cart.fold<double>(0, (s, c) => s + c.quantity);

            final csvPreviewLines = [
              'Symbol;Ilość',
              ...cart
                  .take(5)
                  .map(
                    (c) =>
                        '${c.product.code};${c.quantity.toString().replaceAll('.', ',')}',
                  ),
            ];
            final csvPreview =
                csvPreviewLines.join('\n') + (cart.length > 5 ? '\n…' : '');

            void increment(CartItem item) {
              final maxQty = item.product.quantity;
              final newQty = item.quantity + 1;
              if (newQty <= maxQty) {
                setState(() => item.quantity = newQty);
                setLocal(() {});
                _resetIdleTimer();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Przekroczono dostępny stan (${maxQty.toStringAsFixed(2)})',
                    ),
                  ),
                );
              }
            }

            void decrement(CartItem item) {
              final newQty = item.quantity - 1;
              if (newQty > 0) {
                setState(() => item.quantity = newQty);
              } else {
                setState(
                  () => cart.removeWhere(
                    (c) => c.product.code == item.product.code,
                  ),
                );
              }
              setLocal(() {});
              _resetIdleTimer();
            }

            void editQty(CartItem item, String text) {
              final v = double.tryParse(text.replaceAll(',', '.'));
              if (v == null || v <= 0) return;
              if (v > item.product.quantity) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Maksymalnie ${item.product.quantity.toStringAsFixed(2)}',
                    ),
                  ),
                );
                return;
              }
              setState(() => item.quantity = v);
              setLocal(() {});
              _resetIdleTimer();
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Text(
                      'Koszyk',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: cart.length,
                        separatorBuilder: (context, i) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final item = cart[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(
                              item.product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Kod: ${item.product.code}  |  Stan: ${item.product.quantity.toStringAsFixed(2)}',
                            ),
                            trailing: SizedBox(
                              width: 220,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    onPressed: () => decrement(item),
                                    tooltip: 'Zmniejsz',
                                  ),
                                  SizedBox(
                                    width: 76,
                                    child: TextField(
                                      textAlign: TextAlign.center,
                                      controller: TextEditingController(
                                        text: item.quantity.toStringAsFixed(2),
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      onSubmitted: (t) => editQty(item, t),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 6,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => increment(item),
                                    tooltip: 'Zwiększ',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () {
                                      setState(() => cart.removeAt(i));
                                      setLocal(() {});
                                      _resetIdleTimer();
                                    },
                                    tooltip: 'Usuń z koszyka',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pozycji: $totalLines'),
                              Text(
                                'Suma ilości: ${totalQty.toStringAsFixed(2)}',
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: cart.isEmpty
                              ? null
                              : () {
                                  setState(() => cart.clear());
                                  setLocal(() {});
                                  _resetIdleTimer();
                                },
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Wyczyść koszyk'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Podgląd CSV:',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(top: 6, bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          csvPreview,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                            label: const Text('Zamknij'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: sending
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    _resetIdleTimer();
                                    await sendOrder();
                                  },
                            icon: const Icon(Icons.send),
                            label: const Text('Wyślij zamówienie'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> sendOrder() async {
    if (cart.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Koszyk pusty')));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => sending = true);

    final now = DateTime.now();
    final fname =
        'zamowienie_${user.email!.split('@')[0]}_${now.toIso8601String().replaceAll(':', '-')}.csv';
    final data = [
      ['Symbol', 'Ilość'],
      ...cart.map(
        (c) => [c.product.code, c.quantity.toString().replaceAll('.', ',')],
      ),
    ];
    final csvStr = const ListToCsvConverter(fieldDelimiter: ';').convert(data);

    final url = Uri.parse(
      'https://us-central1-produkty-logowanie.cloudfunctions.net/sendOrderEmail',
    );
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'recipientEmail': 'marcinfranczak@o2.pl',
          'subject': 'Zamówienie od ${user.email}',
          'csvData': csvStr,
          'fileName': fname,
        }),
      );
      if (resp.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Zamówienie wysłane')));
        setState(() => cart.clear());
      } else {
        throw 'HTTP ${resp.statusCode}';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Błąd: $e')));
    }
    if (!mounted) return;
    setState(() => sending = false);
  }

  @override
  Widget build(BuildContext ctx) {
    return Listener(
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerSignal: (_) => _resetIdleTimer(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lista Produktów'),
          actions: [
            // Koszyk
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: sending ? null : showCartPreview,
                  tooltip: 'Podgląd koszyka',
                ),
                if (cart.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        cart.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                if (sending)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Szukaj (nazwa lub kod)',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _resetIdleTimer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Cennik',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedPriceList,
                          items: priceLists
                              .map(
                                (pl) => DropdownMenuItem<String>(
                                  value: pl,
                                  child: Text(
                                    pl.isEmpty ? '(brak)' : pl,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() => selectedPriceList = val);
                            filterProducts();
                            _resetIdleTimer();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : (errorMsg != null
                        ? Center(
                            child: Text(
                              errorMsg!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        : filtered.isEmpty
                        ? const Center(child: Text('Brak produktów'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final p = filtered[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Kod: ${p.code} | Cennik: ${p.priceList}',
                                  ),
                                  trailing: Text(
                                    'Stan: ${p.quantity.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: p.quantity > 0
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onTap: p.quantity > 0
                                      ? () => addToCart(p)
                                      : null,
                                ),
                              );
                            },
                          )),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: loading
              ? null
              : () {
                  _resetIdleTimer();
                  fetchProducts();
                },
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}
