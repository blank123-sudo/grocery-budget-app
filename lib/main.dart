import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const GroceryBudgetApp());
}

class GroceryBudgetApp extends StatelessWidget {
  const GroceryBudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A6D55),
          primary: const Color(0xFF2D4F39),
        ),
      ),
      home: const BudgetTrackerScreen(),
    );
  }
}

// --- MODELS ---

enum Category {
  food(Icons.restaurant, Color(0xFF4A6D55)),
  home(Icons.home_work, Color(0xFF2D4F39)),
  transport(Icons.directions_bus, Color(0xFF8BA888)),
  other(Icons.category, Color(0xFFC1C1C1));

  final IconData icon;
  final Color color;
  const Category(this.icon, this.color);
}

class GroceryItem {
  final String id;
  final String name;
  final double price;
  final DateTime time;
  final Category category;

  GroceryItem({
    required this.id,
    required this.name,
    required this.price,
    required this.time,
    required this.category,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'time': time.toIso8601String(),
        'category': category.name,
      };

  // Create from JSON
  factory GroceryItem.fromJson(Map<String, dynamic> json) => GroceryItem(
        id: json['id'],
        name: json['name'],
        price: (json['price'] as num).toDouble(),
        time: DateTime.parse(json['time']),
        category: Category.values.byName(json['category']),
      );
}

class RecurringExpense {
  final String name;
  final double amount;
  final Category category;
  final List<int> activeDays;

  RecurringExpense({
    required this.name,
    required this.amount,
    required this.category,
    required this.activeDays,
  });
}

// --- MAIN SCREEN ---

class BudgetTrackerScreen extends StatefulWidget {
  const BudgetTrackerScreen({super.key});

  @override
  State<BudgetTrackerScreen> createState() => _BudgetTrackerScreenState();
}

class _BudgetTrackerScreenState extends State<BudgetTrackerScreen> {
  double _monthlyBudget = 0.0;
  final List<GroceryItem> _items = [];
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  double get _totalSpent => _items.fold(0, (sum, item) => sum + item.price);
  double get _remaining => _monthlyBudget - _totalSpent;
  double get _percentUsed => _monthlyBudget == 0 ? 0.0 : (_totalSpent / _monthlyBudget).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // Initial Data Loading
  Future<void> _initializeApp() async {
    await _loadPersistedData();
    if (_monthlyBudget == 0) {
      await _showInitialBudgetPrompt();
    }
    _checkAndAddRecurring();
  }

  // --- PERSISTENCE LOGIC ---

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(
      _items.map((item) => item.toJson()).toList(),
    );
    await prefs.setString('grocery_items', encodedData);
    await prefs.setDouble('monthly_budget', _monthlyBudget);
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? itemsString = prefs.getString('grocery_items');
    final double? savedBudget = prefs.getDouble('monthly_budget');

    setState(() {
      if (itemsString != null) {
        final List<dynamic> decodedData = json.decode(itemsString);
        _items.clear();
        _items.addAll(decodedData.map((item) => GroceryItem.fromJson(item)).toList());
      }
      if (savedBudget != null) {
        _monthlyBudget = savedBudget;
      }
    });
  }

  // --- ACTIONS ---

  Future<void> _showInitialBudgetPrompt() async {
    return _showSetBudgetDialog(isInitialSetup: true);
  }

  void _checkAndAddRecurring() {
    final transpo = RecurringExpense(
      name: 'Daily Transpo',
      amount: 30.0,
      category: Category.transport,
      activeDays: [1, 2, 3, 4, 5],
    );

    final now = DateTime.now();
    if (transpo.activeDays.contains(now.weekday)) {
      bool alreadyAdded = _items.any((item) =>
          item.name == transpo.name &&
          item.time.day == now.day &&
          item.time.month == now.month &&
          item.time.year == now.year);

      if (!alreadyAdded) {
        _performAddItem(transpo.name, transpo.amount, transpo.category);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-logged: ${transpo.name} (${currencyFormat.format(transpo.amount)})'),
            backgroundColor: const Color(0xFF2D4F39),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _performAddItem(String name, double price, Category category) {
    setState(() {
      _items.insert(0, GroceryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        price: price,
        time: DateTime.now(),
        category: category,
      ));
    });
    _saveData();
  }

  void _deleteItem(int index) {
    final deletedItem = _items[index];
    setState(() => _items.removeAt(index));
    _saveData();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${deletedItem.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() => _items.insert(index, deletedItem));
            _saveData();
          },
        ),
      ),
    );
  }

  void _clearAll() {
    setState(() => _items.clear());
    _saveData();
  }

  // --- DIALOGS ---

  Future<void> _showSetBudgetDialog({bool isInitialSetup = false}) {
    final TextEditingController budgetController = TextEditingController(
        text: _monthlyBudget == 0 ? '' : _monthlyBudget.toStringAsFixed(0));

    return showDialog(
      context: context,
      barrierDismissible: !isInitialSetup,
      builder: (context) => PopScope(
        canPop: !isInitialSetup,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(isInitialSetup ? 'Welcome! 👋' : 'Edit Budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isInitialSetup
                    ? 'Please set your monthly budget to begin tracking your expenses.'
                    : 'Adjust your current spending limit.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: budgetController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                    prefixText: '₱ ',
                    labelText: 'Budget Amount',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D4F39),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: () {
                  final double? val = double.tryParse(budgetController.text);
                  if (val != null && val > 0) {
                    setState(() => _monthlyBudget = val);
                    _saveData();
                    Navigator.pop(context);
                  }
                },
                child: Text(isInitialSetup ? 'Start Tracking' : 'Update Budget'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildBudgetCard(),
                  const SizedBox(height: 25),
                  _buildInsights(),
                  const SizedBox(height: 25),
                  _buildListHeader(),
                ],
              ),
            ),
          ),
          _buildItemList(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2D4F39),
        onPressed: _showAddItemSheet,
        label: const Text('Add Item', style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: const Color(0xFFF8F9F8),
      title: const Text('Budget Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
      actions: [
        IconButton(onPressed: () => _showSetBudgetDialog(), icon: const Icon(Icons.tune_rounded)),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildBudgetCard() {
    bool isAlert = _percentUsed > 0.9;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isAlert ? const Color(0xFFFFEBEE) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statTile('Spent', _totalSpent, Colors.black),
              _statTile('Remaining', _remaining, isAlert ? Colors.red : const Color(0xFF4A6D55)),
            ],
          ),
          const SizedBox(height: 15),
          LinearProgressIndicator(
            value: _percentUsed,
            minHeight: 8,
            borderRadius: BorderRadius.circular(10),
            backgroundColor: Colors.grey[200],
            color: isAlert ? Colors.red : const Color(0xFF4A6D55),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, double val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        Text(currencyFormat.format(val), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildInsights() {
    if (_items.isEmpty) return const SizedBox.shrink();
    Map<Category, double> data = {};
    for (var i in _items) {
      data[i.category] = (data[i.category] ?? 0) + i.price;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          SizedBox(
              height: 100,
              width: 100,
              child: PieChart(PieChartData(
                  sections: data.entries
                      .map((e) => PieChartSectionData(color: e.key.color, value: e.value, radius: 15, title: ''))
                      .toList()))),
          const SizedBox(width: 20),
          Expanded(
              child: Column(
                  children: data.entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              CircleAvatar(radius: 4, backgroundColor: e.key.color),
                              const SizedBox(width: 8),
                              Text(e.key.name, style: const TextStyle(fontSize: 12)),
                              const Spacer(),
                              Text(currencyFormat.format(e.value),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
                            ]),
                          ))
                      .toList())),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        TextButton(onPressed: _clearAll, child: const Text('Clear All', style: TextStyle(color: Colors.red))),
      ],
    );
  }

  Widget _buildItemList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final item = _items[index];
        bool isFixed = item.name == 'Daily Transpo';

        return Dismissible(
          key: Key(item.id),
          direction: DismissDirection.endToStart,
          onDismissed: (direction) => _deleteItem(index),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: (isFixed ? Colors.orange : item.category.color).withOpacity(0.1),
                child: Icon(isFixed ? Icons.auto_mode : item.category.icon,
                    color: isFixed ? Colors.orange : item.category.color, size: 20),
              ),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(DateFormat('MMM d, h:mm a').format(item.time)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(currencyFormat.format(item.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _deleteItem(index),
                    child: const Icon(Icons.close, size: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      }, childCount: _items.length),
    );
  }

  void _showAddItemSheet() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => _AddItemSheet(onAdd: _performAddItem));
  }
}

class _AddItemSheet extends StatefulWidget {
  final Function(String, double, Category) onAdd;
  const _AddItemSheet({required this.onAdd});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  Category selectedCat = Category.food;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 25, right: 25, top: 25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item Name')),
          TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price')),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: Category.values
                .map((cat) => GestureDetector(
                      onTap: () => setState(() => selectedCat = cat),
                      child: CircleAvatar(
                          backgroundColor: selectedCat == cat ? cat.color : Colors.grey[200],
                          child: Icon(cat.icon, color: selectedCat == cat ? Colors.white : Colors.grey)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 25),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D4F39),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16)),
                  onPressed: () {
                    final name = nameCtrl.text.isEmpty ? 'Untitled' : nameCtrl.text;
                    final priceText = priceCtrl.text.trim();
                    final double? price = double.tryParse(priceText);

                    if (price == null || price <= 0) {
                      _showErrorDialog(context);
                    } else {
                      widget.onAdd(name, price, selectedCat);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add to List'))),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invalid Price'),
        content: const Text('Please enter a valid amount greater than zero.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF2D4F39))),
          ),
        ],
      ),
    );
  }
}