import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:medisom_console/company/models/company.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompanyService {
  static const _companiesKey = 'companies.v1';
  static const _selectedCompanyKey = 'companies.selectedCompanyId.v1';

  Future<List<Company>> listCompanies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_companiesKey);
      if (raw == null || raw.isEmpty) {
        final seed = _seedCompanies();
        await _saveCompanies(prefs, seed);
        return seed;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('companies is not a list');
      final companies = <Company>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          companies.add(Company.fromJson(item));
        } else if (item is Map) {
          companies.add(Company.fromJson(item.cast<String, dynamic>()));
        }
      }
      return companies;
    } catch (e) {
      debugPrint('CompanyService.listCompanies failed: $e');
      return _seedCompanies();
    }
  }

  Future<String?> getSelectedCompanyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedCompanyKey);
    } catch (e) {
      debugPrint('CompanyService.getSelectedCompanyId failed: $e');
      return null;
    }
  }

  Future<void> setSelectedCompanyId(String companyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedCompanyKey, companyId);
    } catch (e) {
      debugPrint('CompanyService.setSelectedCompanyId failed: $e');
    }
  }

  List<Company> _seedCompanies() {
    final now = DateTime.now();
    return [
      Company(id: 'acme', name: 'ACME Indústria', createdAt: now, updatedAt: now),
      Company(id: 'bluewave', name: 'BlueWave Escritórios', createdAt: now, updatedAt: now),
      Company(id: 'northlab', name: 'NorthLab Câmara Fria', createdAt: now, updatedAt: now),
    ];
  }

  Future<void> _saveCompanies(SharedPreferences prefs, List<Company> companies) async {
    try {
      final raw = jsonEncode(companies.map((c) => c.toJson()).toList());
      await prefs.setString(_companiesKey, raw);
    } catch (e) {
      debugPrint('CompanyService._saveCompanies failed: $e');
    }
  }
}
