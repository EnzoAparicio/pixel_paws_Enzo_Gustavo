equipo = "aparicio-gonzalez"
owner  = "enzo-aparicio"

# repositorio_github y emails_alerta NO van aca: el repo es publico y los mails son
# datos personales. Entran por variables de entorno:
#   GitHub Actions: TF_VAR_repositorio_github sale solo de github.repository, y
#                   TF_VAR_emails_alerta del secret EMAILS_ALERTA.
#   CloudShell:     export TF_VAR_repositorio_github="owner/pixelpaws"
#                   export TF_VAR_emails_alerta='["mail1@x.com","mail2@y.com"]'

# Cuenta AWS propia: se crean el rol de menor privilegio, el OIDC y el presupuesto.
crear_iam_propio = true
# La organizacion que administra la cuenta bloquea los proveedores OIDC (SCP).
# El codigo queda escrito: en la defensa se muestra con
#   terraform plan -var enable_oidc=true
enable_oidc   = false
enable_budget = true

# Extra de la consigna. Dejar en false hasta que el resto funcione: si el filtro
# del evento se rompe, esto genera recursion y cada vuelta es una llamada paga.
mover_clasificadas = false
