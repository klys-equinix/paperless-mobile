import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cm;
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl_standalone.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:paperless_api/paperless_api.dart';
import 'package:paperless_mobile/core/bloc/bloc_changes_observer.dart';
import 'package:paperless_mobile/core/bloc/connectivity_cubit.dart';
import 'package:paperless_mobile/core/bloc/paperless_server_information_cubit.dart';
import 'package:paperless_mobile/core/interceptor/dio_http_error_interceptor.dart';
import 'package:paperless_mobile/core/interceptor/language_header.interceptor.dart';
import 'package:paperless_mobile/core/notifier/document_changed_notifier.dart';
import 'package:paperless_mobile/core/repository/impl/correspondent_repository_impl.dart';
import 'package:paperless_mobile/core/repository/impl/document_type_repository_impl.dart';
import 'package:paperless_mobile/core/repository/impl/saved_view_repository_impl.dart';
import 'package:paperless_mobile/core/repository/impl/storage_path_repository_impl.dart';
import 'package:paperless_mobile/core/repository/impl/tag_repository_impl.dart';
import 'package:paperless_mobile/core/repository/label_repository.dart';
import 'package:paperless_mobile/core/repository/saved_view_repository.dart';
import 'package:paperless_mobile/core/security/session_manager.dart';
import 'package:paperless_mobile/core/service/connectivity_status_service.dart';
import 'package:paperless_mobile/core/service/dio_file_service.dart';
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:paperless_mobile/features/app_intro/application_intro_slideshow.dart';
import 'package:paperless_mobile/features/home/view/home_page.dart';
import 'package:paperless_mobile/features/home/view/widget/verify_identity_page.dart';
import 'package:paperless_mobile/features/login/cubit/authentication_cubit.dart';
import 'package:paperless_mobile/features/login/services/authentication_service.dart';
import 'package:paperless_mobile/features/login/view/login_page.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';
import 'package:paperless_mobile/features/settings/cubit/application_settings_cubit.dart';
import 'package:paperless_mobile/features/sharing/share_intent_queue.dart';
import 'package:paperless_mobile/features/tasks/cubit/task_status_cubit.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/routes/document_details_route.dart';
import 'package:paperless_mobile/theme.dart';
import 'package:paperless_mobile/constants.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:dynamic_color/dynamic_color.dart';

void main() async {
  Bloc.observer = BlocChangesObserver();
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  await findSystemLocale();
  packageInfo = await PackageInfo.fromPlatform();
  if (Platform.isAndroid) {
    androidInfo = await DeviceInfoPlugin().androidInfo;
  }
  if (Platform.isIOS) {
    iosInfo = await DeviceInfoPlugin().iosInfo;
  }

  // Initialize External dependencies
  final connectivity = Connectivity();
  final localAuthentication = LocalAuthentication();
  // Initialize other utility classes
  final connectivityStatusService = ConnectivityStatusServiceImpl(connectivity);
  final localAuthService = LocalAuthenticationService(localAuthentication);

  final hiveDir = await getApplicationDocumentsDirectory();
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: hiveDir,
  );

  final appSettingsCubit = ApplicationSettingsCubit(localAuthService);
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  final languageHeaderInterceptor = LanguageHeaderInterceptor(
    appSettingsCubit.state.preferredLocaleSubtag,
  );
  // Manages security context, required for self signed client certificates
  final sessionManager = SessionManager([
    DioHttpErrorInterceptor(),
    languageHeaderInterceptor,
  ]);

  // Initialize Paperless APIs
  final authApi = PaperlessAuthenticationApiImpl(sessionManager.client);
  final documentsApi = PaperlessDocumentsApiImpl(sessionManager.client);
  final labelsApi = PaperlessLabelApiImpl(sessionManager.client);
  final statsApi = PaperlessServerApi(sessionManager.client);
  final savedViewsApi = PaperlessSavedViewsApiImpl(sessionManager.client);
  final tasksApi = PaperlessTasksApiImpl(
    sessionManager.client,
  );

  // Initialize Blocs/Cubits
  final connectivityCubit = ConnectivityCubit(connectivityStatusService);

  // Load application settings and stored authentication data
  await connectivityCubit.initialize();

  // Create repositories
  final tagRepository = TagRepositoryImpl(labelsApi);
  final correspondentRepository = CorrespondentRepositoryImpl(labelsApi);
  final documentTypeRepository = DocumentTypeRepositoryImpl(labelsApi);
  final storagePathRepository = StoragePathRepositoryImpl(labelsApi);
  final savedViewRepository = SavedViewRepositoryImpl(savedViewsApi);

  //Create cubits/blocs
  final authCubit = AuthenticationCubit(
    localAuthService,
    authApi,
    sessionManager,
  );
  await authCubit.restoreSessionState(
    appSettingsCubit.state.isLocalAuthenticationEnabled,
  );

  if (authCubit.state.isAuthenticated) {
    final auth = authCubit.state.authentication!;
    sessionManager.updateSettings(
      baseUrl: auth.serverUrl,
      authToken: auth.token,
      clientCertificate: auth.clientCertificate,
    );
  }

  final localNotificationService = LocalNotificationService();
  await localNotificationService.initialize();

  //Update language header in interceptor on language change.
  appSettingsCubit.stream.listen((event) => languageHeaderInterceptor
      .preferredLocaleSubtag = event.preferredLocaleSubtag);

  runApp(
    MultiProvider(
      providers: [
        Provider<PaperlessAuthenticationApi>.value(value: authApi),
        Provider<PaperlessDocumentsApi>.value(value: documentsApi),
        Provider<PaperlessLabelsApi>.value(value: labelsApi),
        Provider<PaperlessServerStatsApi>.value(value: statsApi),
        Provider<PaperlessSavedViewsApi>.value(value: savedViewsApi),
        Provider<PaperlessTasksApi>.value(value: tasksApi),
        Provider<cm.CacheManager>(
          create: (context) => cm.CacheManager(
            cm.Config(
              'cacheKey',
              fileService: DioFileService(sessionManager.client),
            ),
          ),
        ),
        Provider<ConnectivityStatusService>.value(
          value: connectivityStatusService,
        ),
        Provider<LocalNotificationService>.value(
            value: localNotificationService),
        Provider.value(value: DocumentChangedNotifier()),
      ],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<LabelRepository<Tag>>.value(
            value: tagRepository,
          ),
          RepositoryProvider<LabelRepository<Correspondent>>.value(
            value: correspondentRepository,
          ),
          RepositoryProvider<LabelRepository<DocumentType>>.value(
            value: documentTypeRepository,
          ),
          RepositoryProvider<LabelRepository<StoragePath>>.value(
            value: storagePathRepository,
          ),
          RepositoryProvider<SavedViewRepository>.value(
            value: savedViewRepository,
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthenticationCubit>.value(value: authCubit),
            BlocProvider<ConnectivityCubit>.value(value: connectivityCubit),
            BlocProvider<ApplicationSettingsCubit>.value(
                value: appSettingsCubit),
          ],
          child: const PaperlessMobileEntrypoint(),
        ),
      ),
    ),
  );
}

class PaperlessMobileEntrypoint extends StatefulWidget {
  const PaperlessMobileEntrypoint({
    Key? key,
  }) : super(key: key);

  @override
  State<PaperlessMobileEntrypoint> createState() =>
      _PaperlessMobileEntrypointState();
}

class _PaperlessMobileEntrypointState extends State<PaperlessMobileEntrypoint> {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => PaperlessServerInformationCubit(
            context.read<PaperlessServerApi>(),
          ),
        ),
      ],
      child: BlocBuilder<ApplicationSettingsCubit, ApplicationSettingsState>(
        builder: (context, settings) {
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              return MaterialApp(
                debugShowCheckedModeBanner: true,
                title: "Paperless Mobile",
                theme: buildTheme(
                  brightness: Brightness.light,
                  dynamicScheme: lightDynamic,
                  preferredColorScheme: settings.preferredColorSchemeOption,
                ),
                darkTheme: buildTheme(
                  brightness: Brightness.dark,
                  dynamicScheme: darkDynamic,
                  preferredColorScheme: settings.preferredColorSchemeOption,
                ),
                themeMode: settings.preferredThemeMode,
                supportedLocales: S.supportedLocales,
                locale: Locale.fromSubtags(
                  languageCode: settings.preferredLocaleSubtag,
                ),
                localizationsDelegates: const [
                  S.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  FormBuilderLocalizations.delegate,
                ],
                routes: {
                  DocumentDetailsRoute.routeName: (context) =>
                      const DocumentDetailsRoute(),
                },
                home: const AuthenticationWrapper(),
              );
            },
          );
        },
      ),
    );
  }
}

class AuthenticationWrapper extends StatefulWidget {
  const AuthenticationWrapper({Key? key}) : super(key: key);

  @override
  State<AuthenticationWrapper> createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  @override
  void didChangeDependencies() {
    FlutterNativeSplash.remove();
    super.didChangeDependencies();
  }

  @override
  void initState() {
    super.initState();
    // Temporary Fix: Can be removed if the flutter engine implements the fix itself
    // Activate the highest supported refresh rate on the device
    if (Platform.isAndroid) {
      _setOptimalDisplayMode();
    }
    initializeDateFormatting();
    // For sharing files coming from outside the app while the app is still opened
    ReceiveSharingIntent.getMediaStream()
        .listen(ShareIntentQueue.instance.addAll);
    // For sharing files coming from outside the app while the app is closed
    ReceiveSharingIntent.getInitialMedia()
        .then(ShareIntentQueue.instance.addAll);
  }

  Future<void> _setOptimalDisplayMode() async {
    final List<DisplayMode> supported = await FlutterDisplayMode.supported;
    final DisplayMode active = await FlutterDisplayMode.active;

    final List<DisplayMode> sameResolution = supported
        .where((m) => m.width == active.width && m.height == active.height)
        .toList()
      ..sort((a, b) => b.refreshRate.compareTo(a.refreshRate));

    final DisplayMode mostOptimalMode =
        sameResolution.isNotEmpty ? sameResolution.first : active;
    debugPrint('Setting refresh rate to ${mostOptimalMode.refreshRate}');

    await FlutterDisplayMode.setPreferredMode(mostOptimalMode);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthenticationCubit, AuthenticationState>(
      listener: (context, authState) {
        final bool showIntroSlider =
            authState.isAuthenticated && !authState.wasLoginStored;
        if (showIntroSlider) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ApplicationIntroSlideshow(),
              fullscreenDialog: true,
            ),
          );
        }
      },
      builder: (context, authentication) {
        if (authentication.isAuthenticated &&
            (authentication.wasLocalAuthenticationSuccessful ?? true)) {
          return BlocProvider(
            create: (context) =>
                TaskStatusCubit(context.read<PaperlessTasksApi>()),
            child: const HomePage(),
          );
        } else {
          if (authentication.wasLoginStored &&
              !(authentication.wasLocalAuthenticationSuccessful ?? false)) {
            return const VerifyIdentityPage();
          }
          return const LoginPage();
        }
      },
    );
  }
}
