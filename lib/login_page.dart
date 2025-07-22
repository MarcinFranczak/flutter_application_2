import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart'; // Zmień nazwę, jeśli Twój plik z listą produktów ma inną nazwę

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  // Tutaj podaj URL do pliku JSON z użytkownikami
  final String usersUrl = 'https://produkty-logowanie.web.app/users.json';

  Future<Map<String, dynamic>> _fetchUsers() async {
    final response = await http.get(Uri.parse(usersUrl));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Błąd pobierania danych użytkowników');
    }
  }

void _login() async {
  if (!mounted) return; // Sprawdzenie na początku
  setState(() {
    _errorMessage = null;
    _isLoading = true;
  });

  try {
    final users = await _fetchUsers();
    final login = _loginController.text.trim();
    final password = _passwordController.text;

    if (users.containsKey(login) && users[login] == password) {
      if (!mounted) return; // Sprawdzenie przed nawigacją
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ProductListPage()),
      );
    } else {
      if (!mounted) return; // Sprawdzenie przed aktualizacją stanu
      setState(() {
        _errorMessage = 'Nieprawidłowy login lub hasło';
      });
    }
  } catch (e) {
    if (!mounted) return; // Sprawdzenie przed aktualizacją stanu
    setState(() {
      _errorMessage = 'Błąd logowania: ${e.toString()}';
    });
  } finally {
    if (mounted) { // Zastąpienie return warunkiem
      setState(() {
        _isLoading = false;
      });
    }
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
              controller: _loginController,
              decoration: const InputDecoration(labelText: 'Login'),
            ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Hasło'),
            ),
            const SizedBox(height: 16),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text('Zaloguj'),
                  ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
