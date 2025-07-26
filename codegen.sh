
#!/bin/bash

# CodeGen - Agente especialista en Linux y desarrollo JavaScript/NodeJS
# Usa la API de Anthropic para análisis de código y consultas técnicas
# Uso: ./codegen [OPCIONES] [CONSULTA]

set -euo pipefail

# Configuración
HISTORIAL_CONVERSACION="codegen_conversation.json"
MAX_TOKENS=${MAX_TOKENS:-2048}
MODEL=${MODEL:-"claude-3-5-sonnet-20241022"}

# Variables para opciones
ARCHIVO_ANALISIS=""
ARCHIVO_OUTPUT=""
MODO_INTERACTIVO=false

# Prompt especializado del agente CodeGen (sin emojis para evitar problemas de encoding)
PROMPT_ESPECIALISTA="Eres CodeGen, un agente especialista en:

PLATAFORMAS LINUX:
- Administracion de sistemas Linux (Ubuntu, CentOS, Arch, etc.)
- Scripting avanzado en Bash y Shell
- Configuracion de servicios y daemons
- Gestion de procesos, usuarios y permisos
- Automatizacion con cron y systemd
- Troubleshooting y optimizacion del sistema

DESARROLLO JAVASCRIPT/NODEJS:
- Desarrollo backend con Node.js y frameworks (Express, Fastify, Koa)
- JavaScript moderno (ES6+, async/await, modulos)
- Gestion de paquetes con npm, yarn, pnpm
- APIs REST y GraphQL
- Bases de datos (MongoDB, PostgreSQL, Redis)
- Testing (Jest, Mocha, Cypress)
- DevOps y deployment (Docker, PM2, Nginx)
- Performance y debugging

Tu objetivo es proporcionar soluciones tecnicas precisas, codigo optimizado y mejores practicas. Siempre incluye ejemplos practicos cuando sea posible."

# Verificar API key
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
    echo "❌ Error: Define la variable ANTHROPIC_API_KEY"                                                                                                                                                                                                                                                     echo "export ANTHROPIC_API_KEY='tu-key-aquí'"
    exit 1
fi

# Verificar dependencias
verificar_dependencias() {
    local dependencias_faltantes=()

    if ! command -v jq &> /dev/null; then
        dependencias_faltantes+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        dependencias_faltantes+=("curl")
    fi

    if [[ ${#dependencias_faltantes[@]} -gt 0 ]]; then
        echo "❌ Error: Faltan dependencias: ${dependencias_faltantes[*]}"
        echo "Instala con: sudo pacman -S ${dependencias_faltantes[*]}"
        exit 1
    fi
}

# Verificar que existe el archivo especificado
verificar_archivo() {
    local archivo="$1"

    if [[ ! -f "$archivo" ]]; then
        echo "❌ Error: No se encontró el archivo '$archivo'"
        echo "Verifica que el archivo existe y la ruta es correcta."
        exit 1
    fi

    local extension="${archivo##*.}"
    local lineas=$(wc -l < "$archivo")
    local tamano_archivo
    tamano_archivo=$(du -h "$archivo" | cut -f1)

    echo "✅ Archivo encontrado: $archivo"
    echo "   📁 Extensión: .$extension | 📄 Líneas: $lineas | 💾 Tamaño: $tamano_archivo"
}

# Leer el contenido del archivo
leer_contenido_archivo() {
    local archivo="$1"
    local contenido=$(cat "$archivo")
    echo "$contenido"
}

# Inicializar historial de conversación (solo para modo interactivo)
inicializar_historial() {
    local contenido_archivo="$1"
    local nombre_archivo="$2"

    # Construir mensaje inicial con prompt especializado
    local mensaje_inicial="$PROMPT_ESPECIALISTA\n\nAhora analiza el siguiente archivo ($nombre_archivo):\n\n\`\`\`\n${contenido_archivo}\n\`\`\`\n\nConfirma que has procesado el archivo y estás listo para consultas técnicas especializadas."

    # Usar jq para crear JSON correctamente escapado
    local mensaje_json=$(echo "$mensaje_inicial" | jq -aRs .)

    # Crear el historial usando jq para asegurar JSON válido
    jq -n --argjson mensaje "$mensaje_json" '{
        messages: [
            {
                role: "user",
                content: $mensaje
            }
        ]
    }' > "$HISTORIAL_CONVERSACION"

    echo "✅ Historial de conversación inicializado con contexto especializado"
}

# Cargar historial existente
cargar_historial() {
    if [[ -f "$HISTORIAL_CONVERSACION" ]]; then
        echo "✅ Cargando historial de conversación existente"
        return 0
    else
        echo "ℹ️  No hay historial previo, inicializando nuevo"
        return 1
    fi
}

# Agregar mensaje al historial
agregar_mensaje() {
    local role="$1"
    local content="$2"

    # Escapar caracteres especiales para JSON
    content=$(echo "$content" | jq -aRs .)

    local temp_file=$(mktemp)
    jq --arg role "$role" --argjson content "$content" \
       '.messages += [{"role": $role, "content": $content}]' \
       "$HISTORIAL_CONVERSACION" > "$temp_file"
    mv "$temp_file" "$HISTORIAL_CONVERSACION"
}

# Obtener mensajes para la API
obtener_mensajes_api() {
    jq -c '.messages' "$HISTORIAL_CONVERSACION"
}

# Realizar consulta CON memoria (solo modo interactivo)
hacer_consulta_con_memoria() {
    local pregunta="$1"

    echo "🔍 Consultando con memoria: '$pregunta'"
    echo "⚡ Procesando con contexto completo..."

    # Agregar la pregunta al historial
    agregar_mensaje "user" "$pregunta"

    # Obtener mensajes para enviar a la API
    local mensajes=$(obtener_mensajes_api)

    # Crear archivo temporal con el JSON payload
    local payload_file=$(mktemp)
    cat > "$payload_file" << EOF
{
    "model": "$MODEL",
    "max_tokens": $MAX_TOKENS,
    "messages": $mensajes
}
EOF

    # Realizar la consulta usando el archivo temporal
    local response=$(curl -s -w "%{http_code}" https://api.anthropic.com/v1/messages \
        --header "x-api-key: $ANTHROPIC_API_KEY" \
        --header "anthropic-version: 2023-06-01" \
        --header "content-type: application/json" \
        --data @"$payload_file")

    # Limpiar archivo temporal
    rm "$payload_file"

    procesar_respuesta_api "$response" "$pregunta" true
}

# Realizar consulta SIN memoria (consulta directa)
hacer_consulta_directa() {
    local pregunta="$1"
    local contenido_archivo="$2"
    local nombre_archivo="$3"

    echo "🔍 Consulta directa: '$pregunta'"
    echo "⚡ Procesando sin memoria conversacional..."

    # Construir mensaje único con contexto especializado
    local mensaje_completo="$PROMPT_ESPECIALISTA"

    if [[ -n "$contenido_archivo" ]]; then
        mensaje_completo+="\n\nAnaliza el siguiente archivo ($nombre_archivo):\n\n\`\`\`\n${contenido_archivo}\n\`\`\`\n\n"
    fi

    mensaje_completo+="Consulta: $pregunta"

    # Escapar correctamente el contenido para JSON
    local mensaje_json=$(echo "$mensaje_completo" | jq -aRs .)

    # Crear archivo temporal con el JSON payload
    local payload_file=$(mktemp)
    cat > "$payload_file" << EOF
{
    "model": "$MODEL",
    "max_tokens": $MAX_TOKENS,
    "messages": [
        {
            "role": "user",
            "content": $mensaje_json
        }
    ]
}
EOF

    # Realizar consulta usando el archivo temporal
    local response=$(curl -s -w "%{http_code}" https://api.anthropic.com/v1/messages \
        --header "x-api-key: $ANTHROPIC_API_KEY" \
        --header "anthropic-version: 2023-06-01" \
        --header "content-type: application/json" \
        --data @"$payload_file")

    # Limpiar archivo temporal
    rm "$payload_file"

    procesar_respuesta_api "$response" "$pregunta" false
}

# Procesar respuesta de la API
procesar_respuesta_api() {
    local response="$1"
    local pregunta="$2"
    local es_con_memoria="$3"

    local http_code="${response: -3}"
    local json_response="${response%???}"

    # Verificar respuesta
    if [[ "$http_code" != "200" ]]; then
        echo "❌ Error HTTP: $http_code"
        echo "$json_response" | jq -r '.error.message // "Error desconocido"'
        return 1
    fi

    # Extraer respuesta
    local respuesta_claude=$(echo "$json_response" | jq -r '.content[0].text')

    if [[ -z "$respuesta_claude" || "$respuesta_claude" == "null" ]]; then
        echo "❌ Error: Respuesta vacía de la API"
        return 1
    fi

    # Si es modo interactivo, agregar respuesta al historial
    if [[ "$es_con_memoria" == true ]]; then
        agregar_mensaje "assistant" "$respuesta_claude"
    fi

    # Mostrar respuesta en consola
    echo ""
    echo "🤖 === RESPUESTA DE CODEGEN ==="
    echo "$respuesta_claude"

    # Guardar en archivo si se especificó --output
    if [[ -n "$ARCHIVO_OUTPUT" ]]; then
        guardar_respuesta_markdown "$pregunta" "$respuesta_claude"
    fi

    # Mostrar info de tokens
    echo ""
    echo "📊 === INFORMACIÓN ==="
    local tokens_entrada=$(echo "$json_response" | jq -r '.usage.input_tokens')
    local tokens_salida=$(echo "$json_response" | jq -r '.usage.output_tokens')

    echo "🔤 Tokens: $tokens_entrada entrada, $tokens_salida salida"

    if [[ "$es_con_memoria" == true ]]; then
        local total_mensajes=$(jq -r '.messages | length' "$HISTORIAL_CONVERSACION")
        echo "💭 Mensajes en memoria: $total_mensajes"
    fi

    if [[ -n "$ARCHIVO_OUTPUT" ]]; then
        echo "💾 Respuesta guardada en: $ARCHIVO_OUTPUT"
    fi
}

# Guardar respuesta en archivo markdown
guardar_respuesta_markdown() {
    local pregunta="$1"
    local respuesta="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "$ARCHIVO_OUTPUT" << EOF
# CodeGen - Consulta Técnica

**Fecha:** $timestamp
**Agente:** CodeGen (Especialista Linux/NodeJS)
**Archivo analizado:** ${ARCHIVO_ANALISIS:-"Ninguno"}

## 🔍 Consulta

$pregunta

## 🤖 Respuesta

$respuesta

---
*Generado por CodeGen - Agente especialista en Linux y desarrollo JavaScript/NodeJS*
EOF

    echo "✅ Respuesta guardada en formato markdown"
}

# Mostrar resumen del historial
mostrar_resumen_historial() {
    if [[ ! -f "$HISTORIAL_CONVERSACION" ]]; then
        echo "ℹ️  No hay historial de conversación"
        return
    fi

    echo "📋 === RESUMEN DEL HISTORIAL ==="
    local total_mensajes=$(jq -r '.messages | length' "$HISTORIAL_CONVERSACION")
    echo "💬 Total de mensajes: $total_mensajes"

    echo ""
    echo "🗨️  Últimos intercambios:"
    jq -r '.messages[-4:] | .[] | "[\(.role | ascii_upcase)]: \(.content[:100])..."' "$HISTORIAL_CONVERSACION" 2>/dev/null || echo "No hay historial suficiente"
}

# Limpiar historial
limpiar_historial() {
    if [[ -f "$HISTORIAL_CONVERSACION" ]]; then
        rm "$HISTORIAL_CONVERSACION"
        echo "🧹 Historial limpiado"
    else
        echo "ℹ️  No hay historial que limpiar"
    fi
}

# Modo interactivo (CON memoria)
modo_interactivo() {
    echo "🚀 === CODEGEN - MODO INTERACTIVO CON MEMORIA ==="
    echo "🔧 Especialista en Linux y desarrollo JavaScript/NodeJS"
    echo ""
    echo "📋 Comandos especiales disponibles:"
    echo "  'salir' - Terminar sesión"
    echo "  'historial' - Ver resumen del historial"
    echo "  'limpiar' - Limpiar historial y reiniciar"
    if [[ -n "$ARCHIVO_ANALISIS" ]]; then
        echo "  'archivo' - Recargar archivo actual ($ARCHIVO_ANALISIS)"
    fi
    echo ""

    while true; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -p "🔍 Tu consulta técnica: " pregunta

        case "$pregunta" in
            "salir")
                echo "👋 ¡Hasta luego! El historial se mantiene para la próxima sesión."
                break
                ;;
            "historial")
                mostrar_resumen_historial
                ;;
            "limpiar")
                limpiar_historial
                if [[ -n "$ARCHIVO_ANALISIS" ]]; then
                    inicializar_historial "$(leer_contenido_archivo "$ARCHIVO_ANALISIS")" "$ARCHIVO_ANALISIS"
                    echo "🔄 Historial reiniciado con el archivo actual"
                else
                    echo "🔄 Historial limpiado, próxima consulta será sin contexto de archivo"
                fi
                ;;
            "archivo")
                if [[ -n "$ARCHIVO_ANALISIS" ]]; then
                    verificar_archivo "$ARCHIVO_ANALISIS"
                    limpiar_historial
                    inicializar_historial "$(leer_contenido_archivo "$ARCHIVO_ANALISIS")" "$ARCHIVO_ANALISIS"
                    echo "🔄 Archivo recargado y historial reiniciado"
                else
                    echo "❌ No hay archivo especificado para recargar"
                fi
                ;;
            "")
                echo "ℹ️  Por favor ingresa una consulta técnica"
                ;;
            *)
                hacer_consulta_con_memoria "$pregunta"
                ;;
        esac
        echo ""
    done
}

# Mostrar ayuda
mostrar_ayuda() {
    cat << EOF
🚀 CodeGen - Agente especialista en Linux y desarrollo JavaScript/NodeJS

DESCRIPCIÓN:
    CodeGen es un agente especializado que utiliza la API de Anthropic para
    proporcionar soluciones técnicas avanzadas en:

    🐧 Plataformas Linux (administración, scripting, troubleshooting)
    💻 Desarrollo JavaScript/NodeJS (backend, APIs, DevOps)

USO:
    $0 [OPCIONES] [CONSULTA]

OPCIONES:
    --interactive, -i           Modo interactivo con memoria conversacional
    --archivo ARCHIVO          Especifica archivo a analizar
    --output ARCHIVO.md        Guarda respuesta en archivo markdown
    --help, -h                 Mostrar esta ayuda
    --clean                    Limpiar historial de memoria
    --status                   Mostrar estado del historial
    --max-tokens NUM           Máximo de tokens (default: 2048)

EJEMPLOS:
    # Modo interactivo básico
    $0 --interactive

    # Analizar archivo en modo interactivo
    $0 --interactive --archivo server.js

    # Consulta directa sin memoria
    $0 "¿Cómo optimizar un servidor Express?"

    # Consulta con archivo y guardar respuesta
    $0 --archivo package.json --output analisis.md "Analiza las dependencias"

    # Combinar opciones
    $0 --archivo script.sh --output revision.md "Revisa este script bash"

ARCHIVOS:
    codegen_conversation.json   Historial de conversación (modo interactivo)

VARIABLES DE ENTORNO:
    ANTHROPIC_API_KEY          Tu clave de API de Anthropic (requerida)
    MAX_TOKENS                 Tokens máximos por defecto
    MODEL                      Modelo por defecto

ESPECIALIZACIÓN:
    CodeGen está optimizado para consultas técnicas sobre desarrollo
    y administración de sistemas. Proporciona código optimizado,
    mejores prácticas y soluciones detalladas.
EOF
}

# Cleanup al salir
cleanup() {
    echo ""
    if [[ "$MODO_INTERACTIVO" == true && -f "$HISTORIAL_CONVERSACION" ]]; then
        echo "💾 El historial se mantiene en $HISTORIAL_CONVERSACION"
    fi
    echo "🏁 CodeGen terminado."
}
trap cleanup EXIT

# Función principal
main() {
    verificar_dependencias

    # Procesar argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                mostrar_ayuda
                exit 0
                ;;
            --interactive|-i)
                MODO_INTERACTIVO=true
                shift
                ;;
            --archivo)
                ARCHIVO_ANALISIS="$2"
                verificar_archivo "$ARCHIVO_ANALISIS"
                shift 2
                ;;
            --output)
                ARCHIVO_OUTPUT="$2"
                # Verificar que termine en .md
                if [[ "$ARCHIVO_OUTPUT" != *.md ]]; then
                    echo "❌ Error: El archivo de salida debe tener extensión .md"
                    exit 1
                fi
                shift 2
                ;;
            --clean)
                limpiar_historial
                exit 0
                ;;
            --status)
                if [[ -f "$HISTORIAL_CONVERSACION" ]]; then
                    mostrar_resumen_historial
                else
                    echo "ℹ️  No hay historial de conversación"
                fi
                exit 0
                ;;
            --max-tokens)
                MAX_TOKENS="$2"
                shift 2
                ;;
            -*)
                echo "❌ Opción desconocida: $1"
                echo "Usa --help para ver todas las opciones disponibles"
                exit 1
                ;;
            *)
                # Es una consulta directa, el resto son argumentos de la consulta
                break
                ;;
        esac
    done

    # Ejecutar según el modo
    if [[ "$MODO_INTERACTIVO" == true ]]; then
        # Modo interactivo CON memoria
        if [[ -n "$ARCHIVO_ANALISIS" ]]; then
            # Con archivo
            if ! cargar_historial; then
                inicializar_historial "$(leer_contenido_archivo "$ARCHIVO_ANALISIS")" "$ARCHIVO_ANALISIS"
                # Hacer consulta inicial para cargar el archivo
                hacer_consulta_con_memoria "Archivo cargado y procesado. Estoy listo para consultas técnicas especializadas." > /dev/null 2>&1 || true
            fi
        else
            # Sin archivo específico
            if ! cargar_historial; then
                # Crear historial básico sin archivo usando jq
                local mensaje_inicial="$PROMPT_ESPECIALISTA\n\nEstoy listo para consultas técnicas especializadas."
                local mensaje_json=$(echo "$mensaje_inicial" | jq -aRs .)

                jq -n --argjson mensaje "$mensaje_json" '{
                    messages: [
                        {
                            role: "user",
                            content: $mensaje
                        }
                    ]
                }' > "$HISTORIAL_CONVERSACION"

                hacer_consulta_con_memoria "Perfecto, estoy listo para ayudarte con consultas técnicas sobre Linux y JavaScript/NodeJS." > /dev/null 2>&1 || true
            fi
        fi
        modo_interactivo
    else
        # Consulta directa SIN memoria
        if [[ $# -eq 0 ]]; then
            echo "❌ Error: Especifica una consulta o usa --interactive"
            echo "Ejemplo: $0 \"¿Cómo configurar nginx en Ubuntu?\""
            echo "O usa: $0 --help para más información"
            exit 1
        fi

        local consulta="$*"
        local contenido_archivo=""

        if [[ -n "$ARCHIVO_ANALISIS" ]]; then
            contenido_archivo="$(leer_contenido_archivo "$ARCHIVO_ANALISIS")"
        fi

        hacer_consulta_directa "$consulta" "$contenido_archivo" "$ARCHIVO_ANALISIS"
    fi
}

# Ejecutar función principal con todos los argumentos
main "$@"