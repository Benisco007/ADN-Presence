class ExportService {
  Future<void> genererRapportSemaine() async {
    throw UnsupportedError('Export non disponible sur web');
  }
  Future<bool> envoyerMailHebdomadaire() async {
    return false; // Not supported on web
  }
  Future<void> exporterHistoriqueEmploye(String userId, String prenom, String nom) async {
    throw UnsupportedError('Export non disponible sur web');
  }
}
