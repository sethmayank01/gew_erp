import 'package:gew_erp/screens/backup.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/saved_reports_screen.dart';
import 'screens/second_input_screen.dart';
import 'screens/test_report_pdf_generator_screen.dart';
import 'screens/test_report_pdf_generator.dart';
import 'screens/user_management_screen.dart';
import 'screens/job_details_screen.dart';
import 'screens/job_list_screen.dart';
import 'screens/material_list_screen.dart';
import 'screens/material_incoming_screen.dart';
import 'screens/stock_view_screen.dart';
import 'screens/job_indent_consumption.dart';
import 'screens/indent_view_screen.dart';
import 'screens/material_outgoing_screen.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
    GoRoute(
      path: '/saved-reports',
      builder: (context, state) => const SavedReportsScreen(),
    ),
    GoRoute(
      path: '/second-input',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>;
        final generalData = args['generalData'];
        final tapCount = args['tapCount'];
        final isEdit = args['isEdit'] ?? false;
        final testData = args['testData']; // ✅ include this

        // Merge testData into generalData so it’s available inside the screen
        if (testData != null) {
          generalData['testData'] = testData;
        }

        return SecondInputScreen(
          generalData: generalData,
          tapCount: tapCount,
          isEdit: isEdit,
        );
      },
    ),
    GoRoute(
      path: '/user-management',
      builder: (context, state) => const UserManagementScreen(),
    ),
    /*GoRoute(
        path: '/test_input_form',
        builder: (_, __) => const TestReportPdfGeneratorScreen()),*/
    GoRoute(
      path: '/test_input_form',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>? ?? {};
        return TestReportPdfGeneratorScreen(
          generalData: args['generalData'],
          tapCount: args['tapCount'],
          isEdit: args['isEdit'] ?? false,
        );
      },
    ),
    GoRoute(
      path: '/preview',
      builder: (context, state) {
        final data = state.extra as Map<String, dynamic>;
        return TestReportPreviewScreen(data: data);
      },
    ),
    GoRoute(
      path: '/job-details',
      builder: (context, state) {
        return JobDetailsScreen();
      },
    ),
    GoRoute(
      path: '/job-list',
      builder: (context, state) {
        return JobListScreen();
      },
    ),
    GoRoute(
      path: '/material-list',
      builder: (context, state) {
        return MaterialListScreen();
      },
    ),
    GoRoute(
      path: '/incoming-material-entry',
      builder: (context, state) {
        return MaterialIncomingScreen();
      },
    ),
    GoRoute(
      path: '/stock-list',
      builder: (context, state) {
        return StockViewScreen();
      },
    ),
    GoRoute(
      path: '/job-indent',
      builder: (context, state) {
        return JobIndentConsumptionScreen();
      },
    ),
    GoRoute(
      path: '/get-job-indent',
      builder: (context, state) {
        return IndentViewScreen();
      },
    ),
    GoRoute(
      path: '/outgoing-material-entry',
      builder: (context, state) {
        return OutgoingMaterialScreen();
      },
    ),
  ],
);
