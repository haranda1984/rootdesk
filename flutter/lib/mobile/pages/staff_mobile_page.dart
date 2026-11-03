import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/staff_page.dart';
import 'package:flutter_hbb/models/staff_model.dart';

import '../../common.dart';
import 'home_page.dart';

/// Pestaña "Casos" de la app móvil del personal (RootDesk Soporte): la misma lista de casos del escritorio.
class StaffMobilePage extends StatelessWidget implements PageShape {
  StaffMobilePage({Key? key}) : super(key: key);

  @override
  final title = translate('Cases');

  @override
  final icon = ListenableBuilder(
    listenable: staffModel,
    builder: (context, _) => Badge(
      isLabelVisible: staffModel.alertas > 0,
      label: Text('${staffModel.alertas}'),
      child: const Icon(Icons.support_agent),
    ),
  );

  @override
  final List<Widget> appBarActions = [];

  @override
  Widget build(BuildContext context) {
    return const Padding(padding: EdgeInsets.fromLTRB(12, 8, 0, 0), child: StaffPage());
  }
}
