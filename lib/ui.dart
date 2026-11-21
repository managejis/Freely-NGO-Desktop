import 'package:flutter/material.dart';

/// Look of the app, after the purple course-app reference: a purple header gradient, big white
/// rounded sheets, a serif display font for headings, blue pill chips, and a white bottom bar with a floating round + button.
const brandBlue = Color(0xFF7A5BF0);
const brandNavy = Color(0xFF2B2F5B);
const skyTop = Color(0xFF7E62F2);
const skyBottom = Color(0xFFC4B8F8);
const lavender = Color(0xFFEDE9FD); // soft blue tint
const panelWhite = Color(0xFFF7F5FF);
const accentOrange = Color(0xFFFDB846);
const accentGreen = Color(0xFF5BC17A);
const accentSky = Color(0xFF42B8F5);
const accentPink = Color(0xFFF0668F);
const accentViolet = Color(0xFF8B6CF0);

const serifFont = 'DMSerif';
const bodyFont = 'Poppins';

/// Heading style. Kept under the old name: it is now Poppins SemiBold (clean and easy to read), slightly smaller than the
/// size given because Poppins is wider than a serif face.
TextStyle serif(double size, {Color? color, FontWeight? weight}) =>
    TextStyle(fontFamily: bodyFont, fontSize: size >= 30 ? size * 0.82 : size * 0.88, color: color, fontWeight: weight ?? FontWeight.w600, height: 1.2, letterSpacing: -0.2);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: brandBlue, brightness: b);
  final cs = dark
      ? base.copyWith(primary: const Color(0xFFB7A5FF), surface: const Color(0xFF15122A))
      : base.copyWith(primary: brandBlue, onPrimary: Colors.white, primaryContainer: const Color(0xFFE3DCFD), onPrimaryContainer: brandNavy, surface: panelWhite);
  final text = (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(fontFamily: bodyFont);
  return ThemeData(
    useMaterial3: true,
    fontFamily: bodyFont,
    colorScheme: cs,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: text.copyWith(
      headlineLarge: serif(34), headlineMedium: serif(30), headlineSmall: serif(26),
      titleLarge: serif(22), titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: serif(24, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: dark ? cs.surfaceContainerHigh : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: brandBlue.withValues(alpha: 0.25),
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: dark ? cs.surfaceContainerHigh : const Color(0xFFECE8FD),
      selectedColor: brandBlue,
      secondarySelectedColor: brandBlue,
      labelStyle: TextStyle(fontFamily: bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: dark ? cs.onSurface : brandNavy),
      secondaryLabelStyle: const TextStyle(fontFamily: bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(const StadiumBorder()),
        side: WidgetStateProperty.all(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brandBlue : (dark ? cs.surfaceContainerHigh : const Color(0xFFECE8FD))),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : (dark ? cs.onSurface : brandNavy)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: const StadiumBorder(), textStyle: const TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600, fontSize: 15))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder(), side: const BorderSide(color: brandBlue))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: const StadiumBorder())),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? cs.surfaceContainerHigh : const Color(0xFFF1EEFD),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: brandBlue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Colors.red)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: brandBlue, foregroundColor: Colors.white, elevation: 6),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), titleTextStyle: serif(22, color: dark ? Colors.white : Colors.black87)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: dark ? cs.surfaceContainer : Colors.white, surfaceTintColor: Colors.transparent, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30)))),
    dividerTheme: DividerThemeData(color: dark ? Colors.white12 : const Color(0xFFE6E2F7)),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: brandNavy, contentTextStyle: const TextStyle(fontFamily: bodyFont, color: Colors.white)),
    listTileTheme: const ListTileThemeData(iconColor: brandBlue),
  );
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color panelColor(BuildContext c) => isDark(c) ? const Color(0xFF15122A) : panelWhite;
Color cardColor(BuildContext c) => isDark(c) ? Theme.of(c).colorScheme.surfaceContainerHigh : Colors.white;

/// The soft blue shadow under cards and tiles.
List<BoxShadow> softShadow(BuildContext c) => [BoxShadow(color: brandBlue.withValues(alpha: isDark(c) ? 0.0 : 0.10), blurRadius: 20, offset: const Offset(0, 6))];

// ====================================================================== background
/// Sky gradient with distant hills and a cross, behind every screen.
class SkyBackground extends StatelessWidget {
  final Widget child;
  const SkyBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dark ? const [Color(0xFF2A2358), Color(0xFF110E22)] : const [skyTop, skyBottom])),
      child: CustomPaint(painter: _HillsPainter(dark), child: child),
    );
  }
}

class _HillsPainter extends CustomPainter {
  final bool dark;
  _HillsPainter(this.dark);
  @override
  void paint(Canvas canvas, Size s) {
    final a = Paint()..color = Colors.white.withValues(alpha: dark ? 0.04 : 0.10);
    canvas.drawCircle(Offset(s.width * 0.92, s.height * 0.06), s.width * 0.34, a);
    canvas.drawCircle(Offset(s.width * 0.05, s.height * 0.22), s.width * 0.22, a);
  }

  @override
  bool shouldRepaint(covariant _HillsPainter old) => old.dark != dark;
}

// ====================================================================== scaffold
/// A screen = the sky background, a header (app bar) on it, and the content on a big white sheet with rounded top corners.
class SkyScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? header, body, floatingActionButton, bottomNavigationBar, drawer;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  /// The content is centred and never wider than this, so lists and forms stay readable on big monitors.
  final double maxWidth;
  const SkyScaffold({super.key, this.maxWidth = 1100, this.appBar, this.header, this.body, this.floatingActionButton, this.floatingActionButtonLocation, this.bottomNavigationBar, this.drawer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      body: Column(children: [
        if (header != null) header!,
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: panelColor(context),
              borderRadius: BorderRadius.vertical(top: const Radius.circular(34), bottom: Radius.circular(bottomNavigationBar == null ? 0 : 0)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(34)), child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: body ?? const SizedBox.shrink()))),
          ),
        ),
      ]),
    );
  }
}

/// Round white icon button used on the gradient (menu, back, ...).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const RoundIconButton({super.key, required this.icon, required this.onTap, this.tooltip = ''});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: brandBlue.withValues(alpha: 0.3),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: brandNavy, size: 22))),
        ),
      );
}

// ====================================================================== bottom bar
class NavItem {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool selected;
  const NavItem(this.icon, this.tip, this.onTap, {this.selected = false});
}

/// White bottom bar with a notch for the floating + button: two icons left, two right.
class BrandBottomBar extends StatelessWidget {
  final List<NavItem> items; // exactly four
  const BrandBottomBar({super.key, required this.items});

  Widget _b(NavItem i) => IconButton(
        tooltip: i.tip,
        onPressed: i.onTap,
        icon: Icon(i.icon, size: 26, color: i.selected ? brandBlue : const Color(0xFF9A96BD)),
      );

  @override
  Widget build(BuildContext context) => BottomAppBar(
        color: panelColor(context),
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: brandBlue.withValues(alpha: 0.35),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _b(items[0]), _b(items[1]), const SizedBox(width: 56), _b(items[2]), _b(items[3]),
        ]),
      );
}

const brandFabLocation = FloatingActionButtonLocation.centerDocked;

class BrandFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const BrandFab({super.key, required this.icon, required this.onPressed, this.tooltip = ''});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64, height: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradientOf(gPurple), boxShadow: [BoxShadow(color: brandBlue.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 8))]),
          child: FloatingActionButton(heroTag: null, shape: const CircleBorder(), tooltip: tooltip, elevation: 0, focusElevation: 0, hoverElevation: 0, highlightElevation: 0, backgroundColor: Colors.transparent, onPressed: onPressed, child: Icon(icon, size: 32)),
        ),
      );
}

// ====================================================================== small pieces
/// White rounded card used for list rows.
class RowCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const RowCard({super.key, required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24), boxShadow: softShadow(context)),
        child: Material(color: Colors.transparent, borderRadius: BorderRadius.circular(24), child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: child)),
      );
}

/// Rounded search field (used on the home screen and in lists).
InputDecoration searchDecoration(String hint) => InputDecoration(
      prefixIcon: const Icon(Icons.search, color: Color(0xFF9A96BD)),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9A96BD), fontSize: 14),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: brandBlue)),
    );

/// A pill with an icon (the "NGO / Connect / Events" chips of the reference).
class PillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const PillChip({super.key, required this.icon, required this.label, required this.onTap, this.filled = false});
  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : brandNavy;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: filled ? brandBlue : (isDark(context) ? Theme.of(context).colorScheme.surfaceContainerHigh : const Color(0xFFECE8FD)),
        shape: const StadiumBorder(),
        elevation: filled ? 4 : 0,
        shadowColor: brandBlue.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: isDark(context) && !filled ? null : fg),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: isDark(context) && !filled ? null : fg, fontWeight: FontWeight.w600, fontSize: 13)),
          ])),
        ),
      ),
    );
  }
}

/// App name in the logo colours (Freely = orange, NGO = blue), bold, on a white pill so it reads on the coloured header.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 3))]),
        child: const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Freely ', style: TextStyle(color: Color(0xFFFF6A00))),
            TextSpan(text: 'NGO', style: TextStyle(color: Color(0xFF0047CC))),
          ]),
          style: TextStyle(fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w800, fontStyle: FontStyle.normal),
        ),
      );
}


// ====================================================================== pastel gradients and tiles
const gPurple = [Color(0xFF9B83F7), Color(0xFF6C4FE8)];
const gOrange = [Color(0xFFFFC36B), Color(0xFFFF9A3D)];
const gPink = [Color(0xFFFF8DB0), Color(0xFFF0527F)];
const gBlue = [Color(0xFF6FD6FB), Color(0xFF3AA8F2)];
const gGreen = [Color(0xFF5EE0BE), Color(0xFF2EC4A0)];

LinearGradient gradientOf(List<Color> c) => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c);

/// Pastel gradient tile: white icon badge, title, small caption.
class GradientTile extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final String title;
  final String? caption;
  final VoidCallback? onTap;
  final double height;
  final Widget? badge;
  const GradientTile({super.key, required this.colors, required this.icon, required this.title, this.caption, this.onTap, this.height = 150, this.badge});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(gradient: gradientOf(colors), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.38), blurRadius: 18, offset: const Offset(0, 10))]),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Stack(children: [
              Positioned(right: -18, top: -18, child: Container(width: 84, height: 84, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.14)))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 4))]),
                    child: badge ?? Icon(icon, color: colors.last, size: 28),
                  ),
                  const Spacer(),
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15, height: 1.2)),
                  if (caption != null) Text(caption!, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
