import 'package:flutter/material.dart';

import 'providers.dart';

/// Pictures a student picks for their card on the "who is studying?" screen.
const _avatars = <(IconData, Color)>[
  (Icons.face, Color(0xFF0F766E)),
  (Icons.face_3, Color(0xFFDB2777)),
  (Icons.rocket_launch, Color(0xFF4338CA)),
  (Icons.star, Color(0xFFD97706)),
  (Icons.pets, Color(0xFF16A34A)),
  (Icons.sports_soccer, Color(0xFF2563EB)),
  (Icons.palette, Color(0xFF9333EA)),
  (Icons.local_florist, Color(0xFFEA580C)),
];

class StudentAvatar extends StatelessWidget {
  const StudentAvatar(this.index, {super.key, this.radius = 28});

  final int index;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _avatars[index % avatarCount];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color, size: radius),
    );
  }
}
