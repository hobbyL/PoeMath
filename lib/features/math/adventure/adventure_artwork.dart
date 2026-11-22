import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';

/// Packaged scenery and collectibles stay independent of saved region IDs.
extension AdventureIllustrations on MathAdventureRegion {
  String get souvenirAsset => 'assets/images/adventure_souvenir_$name.png';
}

class AdventureSouvenir extends StatelessWidget {
  const AdventureSouvenir({
    super.key,
    required this.region,
    this.size = SpacingTokens.xxl,
    this.collected = true,
  });

  final MathAdventureRegion region;
  final double size;
  final bool collected;

  @override
  Widget build(BuildContext context) {
    final artwork = Image.asset(
      region.souvenirAsset,
      width: size,
      height: size,
      cacheWidth: 256,
      fit: BoxFit.contain,
    );
    return ExcludeSemantics(
      child: collected
          ? artwork
          : ColorFiltered(
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: .28),
                BlendMode.srcIn,
              ),
              child: artwork,
            ),
    );
  }
}
