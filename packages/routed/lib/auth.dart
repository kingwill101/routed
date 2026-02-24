export 'src/auth/manager/auth_manager.dart';
export 'src/auth/manager/auth_options.dart';
export 'src/auth/hooks.dart';
export 'src/auth/routes.dart';
export 'src/middleware/basic_auth.dart';
export 'src/middleware/csrf.dart';
export 'src/auth/haigate.dart'
    show
        GateCallback,
        GateEvaluation,
        GateEvaluationContext,
        GateObserver,
        GatePayloadProvider,
        GateDeniedHandler,
        GateRegistry,
        GateRegistrationException,
        GateViolation,
        Haigate;
export 'src/auth/jwt.dart' show jwtAuthentication;
export 'src/auth/provider.dart' show AuthServiceProvider;
export 'src/auth/rbac.dart'
    show
        registerRbacAbilities,
        registerRbacAbilitiesSafely,
        registerRbacWithHaigate,
        rbacGate;
export 'src/auth/policies.dart'
    show
        policyGate,
        registerPolicyBindings,
        registerPolicyBindingsSafely,
        registerPoliciesWithHaigate;

export 'src/auth/oauth.dart' show oauth2Introspection;
export 'src/auth/session_auth.dart'
    show
        SessionAuthService,
        SessionAuth,
        GuardResult,
        AuthGuard,
        GuardRegistry,
        guardMiddleware,
        requireAuthenticated,
        requireRoles;
