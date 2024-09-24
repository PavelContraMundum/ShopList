import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() {
  runApp(ShoppingListApp());
}

class ShoppingListApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ShoppingListScreen(),
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
    );
  }
}

class ShoppingListScreen extends StatefulWidget {
  @override
  _ShoppingListScreenState createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  Database? _database;
  final List<Map<String, dynamic>> _stores = [];
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _itemController = TextEditingController();
  String? _selectedStoreId;
  bool _showInputFields = false; // Stav pro zobrazení/skrytí inputů

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'shopping_list.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE stores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            bought INTEGER NOT NULL,
            store_id INTEGER NOT NULL,
            FOREIGN KEY (store_id) REFERENCES stores (id)
          )
        ''');
      },
    );

    _loadStores();
  }

  Future<void> _loadStores() async {
    final stores = await _database!.query('stores');
    final storeList = stores.map((store) {
      return {
        'id': store['id'],
        'name': store['name'],
        'items': [],
      };
    }).toList();

    for (var store in storeList) {
      final items = await _database!.query('items',
          where: 'store_id = ?', whereArgs: [store['id']]);
      store['items'] = List.from(items); // Kopie seznamu položek
    }

    setState(() {
      _stores.clear();
      _stores.addAll(storeList);
    });
  }

  Future<void> _addStore() async {
    if (_storeController.text.isNotEmpty) {
      final id = await _database!.insert('stores', {
        'name': _storeController.text,
      });
      setState(() {
        _stores.add({'id': id, 'name': _storeController.text, 'items': []});
      });
      _storeController.clear();
      _selectedStoreId = id.toString(); // Automaticky vybrat přidaný obchod
    }
  }

  Future<void> _addItem() async {
    if (_itemController.text.isNotEmpty && _selectedStoreId != null) {
      final id = await _database!.insert('items', {
        'name': _itemController.text,
        'bought': 0,
        'store_id': int.parse(_selectedStoreId!),
      });

      final storeIndex =
      _stores.indexWhere((store) => store['id'].toString() == _selectedStoreId);

      setState(() {
        _stores[storeIndex]['items'] = List.from(_stores[storeIndex]['items'])
          ..add({
            'id': id,
            'name': _itemController.text,
            'bought': 0,
          });
      });

      _itemController.clear();
    }
  }

  Future<void> _toggleItem(int storeIndex, int itemIndex) async {
    final item = _stores[storeIndex]['items'][itemIndex];
    final updatedBought = item['bought'] == 0 ? 1 : 0;

    await _database!.update(
      'items',
      {'bought': updatedBought},
      where: 'id = ?',
      whereArgs: [item['id']],
    );

    setState(() {
      _stores[storeIndex]['items'][itemIndex] = {
        ...item,
        'bought': updatedBought,
      };
    });
  }

  Future<void> _removeItem(int storeIndex, int itemIndex) async {
    final itemId = _stores[storeIndex]['items'][itemIndex]['id'];

    await _database!.delete(
      'items',
      where: 'id = ?',
      whereArgs: [itemId],
    );

    setState(() {
      _stores[storeIndex]['items'] = List.from(_stores[storeIndex]['items']);
      _stores[storeIndex]['items'].removeAt(itemIndex);
    });
  }

  Future<void> _removeStore(int storeIndex) async {
    final storeId = _stores[storeIndex]['id'];

    // Odstranit všechny položky spojené s obchodem
    await _database!.delete(
      'items',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );

    // Odstranit obchod
    await _database!.delete(
      'stores',
      where: 'id = ?',
      whereArgs: [storeId],
    );

    setState(() {
      _stores.removeAt(storeIndex);

      // Pokud byl odstraněn aktuálně vybraný obchod, vymazat výběr
      if (_selectedStoreId == storeId.toString()) {
        _selectedStoreId = null;
      }
    });
  }

  @override
  void dispose() {
    _database?.close();
    _storeController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nákupní lístek'),
        actions: [
          IconButton(
            icon: Icon(_showInputFields ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _showInputFields = !_showInputFields;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showInputFields) ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _storeController,
                      decoration: InputDecoration(
                        labelText: 'Přidat obchod',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add),
                    onPressed: _addStore,
                  ),
                ],
              ),
            ),
            if (_stores.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButton<String>(
                  hint: Text('Vybrat obchod'),
                  value: _selectedStoreId,
                  onChanged: (value) {
                    setState(() {
                      _selectedStoreId = value;
                    });
                  },
                  items: _stores.map<DropdownMenuItem<String>>((store) {
                    return DropdownMenuItem<String>(
                      value: store['id'].toString(),
                      child: Text(store['name']),
                    );
                  }).toList(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _itemController,
                      decoration: InputDecoration(
                        labelText: 'Přidat zboží k vybranému obchodu',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add),
                    onPressed: _addItem,
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: ListView.builder(
              itemCount: _stores.length,
              itemBuilder: (context, storeIndex) {
                final store = _stores[storeIndex];
                return ExpansionTile(
                  title: Text(store['name']),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _removeStore(storeIndex),
                  ),
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: ClampingScrollPhysics(),
                      itemCount: store['items'].length,
                      itemBuilder: (context, itemIndex) {
                        final item = store['items'][itemIndex];
                        return ListTile(
                          title: Text(
                            item['name'],
                            style: TextStyle(
                              decoration: item['bought'] == 1
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          leading: Checkbox(
                            value: item['bought'] == 1,
                            onChanged: (value) {
                              _toggleItem(storeIndex, itemIndex);
                            },
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () => _removeItem(storeIndex, itemIndex),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
