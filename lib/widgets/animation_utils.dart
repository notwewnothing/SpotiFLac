import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Staggered List Item – fade + slide-up entrance with index-based delay
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a child in a staggered fade-in + slide-up animation.
///
/// [index] controls the stagger delay (each item delayed by [staggerDelay]).
/// Set [animate] to false to skip the animation (e.g. when scrolling back).
class StaggeredListItem extends StatelessWidget {
  static const int _defaultMaxAnimatedItems = 10;

  final int index;
  final Widget child;
  final Duration duration;
  final Duration staggerDelay;
  final bool animate;
  final int maxAnimatedItems;

  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    this.staggerDelay = const Duration(milliseconds: 40),
    this.animate = true,
    this.maxAnimatedItems = _defaultMaxAnimatedItems,
  });

  @override
  Widget build(BuildContext context) {
    if (!animate || index >= maxAnimatedItems) return child;
    // Cap the delay so very long lists don't have absurd wait times.
    final cappedIndex = index.clamp(0, maxAnimatedItems - 1);
    final delay = staggerDelay * cappedIndex;
    final totalDuration = duration + delay;

    return TweenAnimationBuilder<double>(
      key: ValueKey('stagger_$index'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: totalDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        // Compute the effective progress after the stagger delay.
        final delayFraction = totalDuration.inMilliseconds > 0
            ? delay.inMilliseconds / totalDuration.inMilliseconds
            : 0.0;
        final progress = value <= delayFraction
            ? 0.0
            : ((value - delayFraction) / (1.0 - delayFraction)).clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Animated State Switcher – crossfade between loading / content / empty / error
// ─────────────────────────────────────────────────────────────────────────────

/// A convenience wrapper around [AnimatedSwitcher] that crossfades between
/// different widget states (loading, content, empty, error).
///
/// Assign a unique [ValueKey] to each child so the switcher detects changes.
class AnimatedStateSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const AnimatedStateSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Shared Page Route – consistent slide-from-right transition
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a platform-aware material route.
///
/// This intentionally defers route transitions to Flutter's material route and
/// theme so Android predictive back and platform-default animations remain
/// intact.
Route<T> slidePageRoute<T>({required Widget page}) {
  return MaterialPageRoute<T>(builder: (context) => page);
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Shimmer / Skeleton Loading Widget
// ─────────────────────────────────────────────────────────────────────────────

/// A shimmer effect widget that can wrap skeleton placeholders.
class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainerHigh;
    final highlightColor = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A skeleton placeholder box used inside [ShimmerLoading].
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Track list skeleton – mimics a list of track items while loading.
class TrackListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showCoverHeader;

  const TrackListSkeleton({
    super.key,
    this.itemCount = 8,
    this.showCoverHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return ShimmerLoading(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            if (showCoverHeader) ...[
              SkeletonBox(
                width: screenWidth,
                height: screenWidth * 0.75,
                borderRadius: 0,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SkeletonBox(width: 180, height: 20, borderRadius: 4),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 20),
                child: SkeletonBox(width: 110, height: 14, borderRadius: 4),
              ),
            ],
            ...List.generate(itemCount, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const SkeletonBox(width: 48, height: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 140 + (index % 3) * 30,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: 90 + (index % 2) * 20,
                            height: 12,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SkeletonBox(width: 24, height: 24, borderRadius: 12),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Grid skeleton – mimics a grid of album/playlist cards while loading.

/// Album track list skeleton – mimics the album screen track list layout
/// (track number + title + artist + trailing icon, no cover art thumbnail).
class AlbumTrackListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showCoverHeader;

  const AlbumTrackListSkeleton({
    super.key,
    this.itemCount = 10,
    this.showCoverHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return ShimmerLoading(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            if (showCoverHeader) ...[
              SkeletonBox(
                width: screenWidth,
                height: screenWidth * 0.75,
                borderRadius: 0,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SkeletonBox(width: 180, height: 20, borderRadius: 4),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 20),
                child: SkeletonBox(width: 110, height: 14, borderRadius: 4),
              ),
            ],
            ...List.generate(itemCount, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Center(
                        child: SkeletonBox(
                          width: 14,
                          height: 14,
                          borderRadius: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 120 + (index % 4) * 35,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: 70 + (index % 3) * 20,
                            height: 12,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SkeletonBox(width: 20, height: 20, borderRadius: 10),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class GridSkeleton extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;

  const GridSkeleton({super.key, this.itemCount = 6, this.crossAxisCount = 2});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AspectRatio(
                  aspectRatio: 1,
                  child: SkeletonBox(width: double.infinity, height: 0),
                ),
                const SizedBox(height: 8),
                SkeletonBox(
                  width: 80 + (index % 3) * 20,
                  height: 12,
                  borderRadius: 4,
                ),
                const SizedBox(height: 4),
                SkeletonBox(
                  width: 50 + (index % 2) * 15,
                  height: 10,
                  borderRadius: 4,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Artist screen skeleton – mimics the artist page content below the header:
/// an optional "Popular" section (rank + cover 48x48 + title + trailing) then
/// a horizontal-scroll album section.
class ArtistScreenSkeleton extends StatelessWidget {
  final int popularCount;
  final int albumCount;

  const ArtistScreenSkeleton({
    super.key,
    this.popularCount = 5,
    this.albumCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return ShimmerLoading(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(
              width: screenWidth,
              height: screenWidth * 0.75,
              borderRadius: 0,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: SkeletonBox(width: 180, height: 24, borderRadius: 4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SkeletonBox(width: 120, height: 14, borderRadius: 4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SkeletonBox(width: 90, height: 20, borderRadius: 4),
            ),
            ...List.generate(popularCount, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Center(
                        child: SkeletonBox(
                          width: 12,
                          height: 14,
                          borderRadius: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const SkeletonBox(width: 48, height: 48, borderRadius: 4),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 110 + (index % 4) * 30,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: 70 + (index % 3) * 15,
                            height: 11,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SkeletonBox(width: 20, height: 20, borderRadius: 10),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SkeletonBox(width: 80, height: 20, borderRadius: 4),
            ),
            SizedBox(
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: albumCount,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonBox(width: 140, height: 140),
                        const SizedBox(height: 8),
                        SkeletonBox(
                          width: 80 + (index % 3) * 20,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 4),
                        SkeletonBox(
                          width: 50 + (index % 2) * 15,
                          height: 10,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home search skeleton – mimics filter chips + sectioned results
/// (Artists section with rounded card items, Albums section, etc.)
class HomeSearchSkeleton extends StatelessWidget {
  const HomeSearchSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SkeletonBox(width: 48, height: 32, borderRadius: 16),
                const SizedBox(width: 8),
                SkeletonBox(width: 64, height: 32, borderRadius: 16),
                const SizedBox(width: 8),
                SkeletonBox(width: 72, height: 32, borderRadius: 16),
                const SizedBox(width: 8),
                SkeletonBox(width: 60, height: 32, borderRadius: 16),
                const SizedBox(width: 8),
                SkeletonBox(width: 70, height: 32, borderRadius: 16),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _sectionSkeleton(context, 70, 2),
          const SizedBox(height: 16),
          _sectionSkeleton(context, 65, 4),
        ],
      ),
    );
  }

  static Widget _sectionSkeleton(
    BuildContext context,
    double headerWidth,
    int itemCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SkeletonBox(width: headerWidth, height: 18, borderRadius: 4),
              const Spacer(),
              const SkeletonBox(width: 50, height: 16, borderRadius: 4),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: List.generate(itemCount, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const SkeletonBox(width: 48, height: 48, borderRadius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 100 + (index % 3) * 40,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: 60 + (index % 2) * 25,
                            height: 12,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SkeletonBox(width: 20, height: 20, borderRadius: 10),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Animated Selection Checkbox – scales in when entering selection mode
// ─────────────────────────────────────────────────────────────────────────────

/// An animated selection indicator that scales in/out and crossfades the
/// checked/unchecked state.
class AnimatedSelectionCheckbox extends StatelessWidget {
  final bool visible;
  final bool selected;
  final ColorScheme colorScheme;
  final double size;

  /// Background color when not selected. Defaults to `Colors.transparent`.
  final Color? unselectedColor;

  const AnimatedSelectionCheckbox({
    super.key,
    required this.visible,
    required this.selected,
    required this.colorScheme,
    this.size = 20,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : unselectedColor ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
            width: 2,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: selected
              ? Icon(
                  Icons.check,
                  key: const ValueKey('checked'),
                  size: size - 6,
                  color: colorScheme.onPrimary,
                )
              : SizedBox(
                  key: const ValueKey('unchecked'),
                  width: size - 6,
                  height: size - 6,
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Download Success Animation – green flash + checkmark
// ─────────────────────────────────────────────────────────────────────────────

/// A widget that briefly flashes a success color behind its child and shows
/// an animated checkmark when [showSuccess] transitions to true.
class DownloadSuccessOverlay extends StatefulWidget {
  final bool showSuccess;
  final Widget child;

  const DownloadSuccessOverlay({
    super.key,
    required this.showSuccess,
    required this.child,
  });

  @override
  State<DownloadSuccessOverlay> createState() => _DownloadSuccessOverlayState();
}

class _DownloadSuccessOverlayState extends State<DownloadSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flashAnimation;
  late bool _wasSuccess;

  @override
  void initState() {
    super.initState();
    // Initialise from the current widget value so items that are already
    // completed when first built do not play the flash animation.
    _wasSuccess = widget.showSuccess;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.15), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.0), weight: 70),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(DownloadSuccessOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSuccess && !_wasSuccess) {
      _controller.forward(from: 0);
    }
    _wasSuccess = widget.showSuccess;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: _flashAnimation.value),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Badge Bump Animation – scales the badge when count changes
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a [Badge] child and plays a brief scale-bump whenever [count] changes.
class AnimatedBadge extends StatefulWidget {
  final int count;
  final Widget child;

  const AnimatedBadge({super.key, required this.count, required this.child});

  @override
  State<AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _previousCount = widget.count;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 60),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != _previousCount && widget.count > _previousCount) {
      _controller.forward(from: 0);
    }
    _previousCount = widget.count;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. Animated Removal Item – fade + slide out when removed from a list
// ─────────────────────────────────────────────────────────────────────────────

/// Build a removal animation for [AnimatedList] items.
/// Use as the `builder` callback in [AnimatedListState.removeItem].
Widget buildRemovalAnimation(Widget child, Animation<double> animation) {
  return SizeTransition(
    sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
    child: FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
      child: child,
    ),
  );
}
