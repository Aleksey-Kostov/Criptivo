/// Кой може да види поле от профила.
enum ProfileVisibility {
  nobody,
  everyone;

  static ProfileVisibility fromDb(String? raw) {
    switch (raw) {
      case 'everyone':
        return ProfileVisibility.everyone;
      case 'nobody':
      default:
        return ProfileVisibility.nobody;
    }
  }

  String get db => name;

  String get labelBg {
    switch (this) {
      case ProfileVisibility.nobody:
        return 'Само аз';
      case ProfileVisibility.everyone:
        return 'Всички';
    }
  }
}
