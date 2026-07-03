import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcının son girdiği araç bilgileri (model, renk, not).
class CarpoolVehiclePrefs {
  final String? carModel;
  final String? carColor;
  final String? notes;

  const CarpoolVehiclePrefs({
    this.carModel,
    this.carColor,
    this.notes,
  });

  bool get isEmpty =>
      (carModel == null || carModel!.isEmpty) &&
      (carColor == null || carColor!.isEmpty) &&
      (notes == null || notes!.isEmpty);
}

/// Ortak yolculuk ilanı formunda araç bilgilerini cihazda saklar.
class CarpoolVehiclePrefsStorage {
  static String _key(String userId, String field) =>
      'carpool_vehicle_prefs.$userId.$field';

  Future<CarpoolVehiclePrefs> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return CarpoolVehiclePrefs(
      carModel: prefs.getString(_key(userId, 'car_model')),
      carColor: prefs.getString(_key(userId, 'car_color')),
      notes: prefs.getString(_key(userId, 'notes')),
    );
  }

  Future<void> save(
    String userId, {
    required String carModel,
    required String carColor,
    required String notes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _setOrRemove(prefs, _key(userId, 'car_model'), carModel);
    await _setOrRemove(prefs, _key(userId, 'car_color'), carColor);
    await _setOrRemove(prefs, _key(userId, 'notes'), notes);
  }

  Future<void> _setOrRemove(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}
