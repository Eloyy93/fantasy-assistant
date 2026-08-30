import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Envoltorio fino sobre Firebase Auth + Google Sign-In. Iniciar sesión es
/// opcional en toda la app — quien no lo hace sigue funcionando con su
/// device_id local de siempre (ver device_id.dart y api_client.dart).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  User? get usuarioActual => FirebaseAuth.instance.currentUser;

  Stream<User?> get cambiosDeSesion => FirebaseAuth.instance.authStateChanges();

  /// Token que hay que mandar en la cabecera Authorization de la API
  /// (`Bearer <token>`) — null si no hay sesión iniciada.
  Future<String?> tokenActual() => usuarioActual?.getIdToken() ?? Future.value(null);

  Future<User?> iniciarSesionConGoogle() async {
    final UserCredential credencial;
    if (kIsWeb) {
      // En web, Firebase Auth abre su propio popup de Google — no hace
      // falta pasar por el SDK nativo de google_sign_in.
      credencial = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } else {
      final cuenta = await _googleSignIn.signIn();
      if (cuenta == null) return null; // el usuario canceló el diálogo
      final auth = await cuenta.authentication;
      final credencialGoogle = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      credencial = await FirebaseAuth.instance.signInWithCredential(credencialGoogle);
    }
    return credencial.user;
  }

  Future<void> cerrarSesion() async {
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb) await _googleSignIn.signOut();
  }
}
