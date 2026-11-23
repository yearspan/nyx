import 'dart:math';

import 'package:material_ui/material_ui.dart';

class EmptyPage extends StatelessWidget {
  static const double _width = 400;
  const EmptyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final width = min(MediaQuery.sizeOf(context).width, EmptyPage._width) / 2;
    return Scaffold(
      // Add invisible appbar to make status bar on Android tablets bright.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        alignment: Alignment.center,
        child: ClipOval(child:
        Image.asset(
          'assets/logo/mini/logo_mini.png',
          width: width,
          height: width,
          filterQuality: FilterQuality.medium,
        ),)
      ),
    );
  }
}
