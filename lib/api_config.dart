class ApiConfig {
  // Toggle this to switch between LAN and cloud environments
  static const bool useLocalServer = true;

  static String get baseUrl => useLocalServer
      ? 'http://192.168.2.110:5000/api' // Replace with your actual LAN IP
      : 'https://your-cloud-api.com/api'; // Replace with your cloud server
}
