import 'package:cat_ship/data/udp_services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:cat_ship/data/settings.dart';
import 'components/home_page.dart';

Data globalData = Data();

void main() async {
  ///wait until the binding is ready
  WidgetsFlutterBinding.ensureInitialized();

  ///load settings
  await globalData.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final myServices = UdpServices();
            myServices.startMyServices();
            return myServices;
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cat Ship',
      localizationsDelegates: const [
        AppLocalizations.delegate, //this is the real lacalisation
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''), // English, no country code
        Locale('de', ''), // German, no country code
      ],
      locale: Locale(globalData.settings.locale ?? 'en'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
