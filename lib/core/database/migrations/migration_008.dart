import 'package:sqflite/sqflite.dart';

/// Adds local, user-scoped monthly budgets and savings goals.
Future<void> applyMigration008(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS monthly_budgets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      period_month TEXT NOT NULL,
      limit_minor INTEGER NOT NULL CHECK (limit_minor > 0),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(user_id, period_month)
    )
  ''');
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_monthly_budgets_user_month '
    'ON monthly_budgets(user_id, period_month)',
  );

  await database.execute('''
    CREATE TABLE IF NOT EXISTS savings_goals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      target_minor INTEGER NOT NULL CHECK (target_minor > 0),
      saved_minor INTEGER NOT NULL DEFAULT 0 CHECK (saved_minor >= 0),
      due_date TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_savings_goals_user '
    'ON savings_goals(user_id, created_at)',
  );
}
