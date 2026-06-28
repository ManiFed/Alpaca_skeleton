import 'package:flutter/widgets.dart';

class AladinSky extends StatelessWidget {
  const AladinSky({
    super.key,
    this.ra,
    this.dec,
    this.fov = 65,
    this.targetLabel,
    this.drift = true,
  });

  final double? ra;
  final double? dec;
  final double fov;
  final String? targetLabel;
  final bool drift;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
