/// Edición de la aplicación: `cliente` (la que se entrega a los clientes) o `staff` (RootDesk Soporte, para el
/// personal). El flujo de compilación de la edición del personal reescribe esta constante antes de compilar.
const String kEdition = 'cliente';

bool get isStaffEdition => kEdition == 'staff';
