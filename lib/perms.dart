/// Permissions the owner can give to each staff member.
/// The owner always has every permission.
class Perm {
  static const String sell = 'sell';
  static const String credit = 'credit';
  static const String viewCost = 'view_cost';
  static const String addInventory = 'add_inventory';
  static const String dashboard = 'dashboard';
  static const String reports = 'reports';
  static const String edit = 'edit';

  static const List<String> all = [
    sell,
    credit,
    viewCost,
    addInventory,
    dashboard,
    reports,
    edit,
  ];

  /// What a new staff member gets by default.
  static const List<String> defaultStaff = [sell, credit];

  static const Map<String, String> labels = {
    sell: 'Record sales',
    credit: 'Add credit entries and customer payments',
    viewCost: 'See purchase prices and profit / loss',
    addInventory: 'Add inventory (new stock)',
    dashboard: 'View the Dashboard',
    reports: 'Download Excel / PDF reports',
    edit: 'Delete past entries',
  };
}
