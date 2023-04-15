#!/bin/bash

# Déclarer les variables
LOGFILE="sync.log"
DIR1="dir1"
DIR2="dir2"

# Vérifier les paramètres de ligne de commande
if [ $# -ne 3 ]; then+
  echo "Usage: $0 <directory1> <directory2> <log_file>" >&2
  exit 1
fi

# Obtenir le répertoire et le nom du journal
dir1="$1"
dir2="$2"
log_file="$3"

# Vérifiez si le fichier journal existe. S’il n’existe pas, créez un fichier journal vide. Si vous ne pouvez pas le créer, imprimez un message d’erreur et quittez
if [ ! -f "$LOGFILE" ]; then
  if ! touch "$LOGFILE"; then
    echo "Error: Cannot create log file $LOGFILE" >&2
    exit 1
  fi
fi

#Vérifier l’existence de répertoires: avant de comparer des fichiers dans un répertoire, vous devez vérifier l’existence de ces répertoires. Si le répertoire n’existe pas, affiche le message d’erreur et quitte le programme.
if [ ! -d "$dir1" ] || [ ! -d "$dir2" ]; then
  echo "Error: Directories $dir1 and/or $dir2 do not exist." >&2
  exit 1
fi

# Définit une fonction pour comparer les métadonnées des fichiers, retourne 0 si les deux fichiers sont identiques, sinon affiche un message d’erreur et retourne 1
metadata_compare() {
  file1=$1
  file2=$2
  if [ ! -e "$file1" ] || [ ! -e "$file2" ]; then
  # Sauter si l’un des fichiers n’existe pas
  continue
elif [ -L "$file1" ] || [ -L "$file2" ]; then
  # Sauter si l’un des fichiers est un lien symbolique
  continue
elif [ -d "$file1" ] && [ ! -d "$file2" ]; then
  # Il y a un conflit si le premier fichier est un répertoire, mais le second ne l’est pas
  echo "Conflict: $file1 is a directory, but $file2 is not." >&2
  return 1
elif [ ! -d "$file1" ] && [ -d "$file2" ]; then
  # Il y a un conflit si le premier fichier est normal mais le second ne l’est pas
  echo "Conflict: $file1 is a regular file, but $file2 is a directory." >&2
  return 1
fi
  if [ "$(stat -c "%s:%y:%a" "$file1")" = "$(stat -c "%s:%y:%a" "$file2")" ]; then
    return 0
  else
    echo "Error: Cannot compare metadata of $file1 and $file2" >&2
    return 1
  fi
}

# Définit une fonction pour comparer le contenu des fichiers, retourne 0 si les deux fichiers ont le même contenu, sinon retourne 1
content_compare() {
  file1=$1
  file2=$2
  if [ ! -e "$file1" ] || [ ! -e "$file2" ]; then
  # Sauter si l’un des fichiers n’existe pas
  continue
elif [ -L "$file1" ] || [ -L "$file2" ]; then
  # Sauter si l’un des fichiers est un lien symbolique
  continue
elif [ -d "$file1" ] && [ ! -d "$file2" ]; then
  # Il y a un conflit si le premier fichier est un répertoire, mais le second ne l’est pas
  echo "Conflict: $file1 is a directory, but $file2 is not." >&2
  return 1
elif [ ! -d "$file1" ] && [ -d "$file2" ]; then
  # Il y a un conflit si le premier fichier est normal mais le second ne l’est pas
  echo "Conflict: $file1 is a regular file, but $file2 is a directory." >&2
  return 1
fi
  if cmp -s "$file1" "$file2"; then
    return 0
  else
    echo "Error: Cannot compare content of $file1 and $file2" >&2
    return 1
  fi
}

# Définissez la fonction pour synchroniser les deux fichiers, renvoyant 0 si la synchronisation est réussie, 1 sinon.
sync_file() {
  file1=$1
  file2=$2
  if [ ! -e "$file1" ] || [ ! -e "$file2" ]; then
  # Sauter si l’un des fichiers n’existe pas
  continue
elif [ -L "$file1" ] || [ -L "$file2" ]; then
  # Sauter si l’un des fichiers est un lien symbolique
  continue
elif [ -d "$file1" ] && [ ! -d "$file2" ]; then
  # Il y a un conflit si le premier fichier est un répertoire, mais le second ne l’est pas
  echo "Conflict: $file1 is a directory, but $file2 is not." >&2
  return 1
elif [ ! -d "$file1" ] && [ -d "$file2" ]; then
  # Il y a un conflit si le premier fichier est normal mais le second ne l’est pas
  echo "Conflict: $file1 is a regular file, but $file2 is a directory." >&2
  return 1
fi
  if metadata_compare "$file1" "$file2"; then
    # Si les métadonnées des deux fichiers sont identiques, aucune synchronisation n’est nécessaire et 0 est retourné directement
    return 0
  elif content_compare "$file1" "$file2"; then
    # Si les deux fichiers ont le même contenu, les métadonnées du fichier sont mises à jour et le résultat est stocké dans un fichier journal
    touch -r "$file2" "$file1"
    chmod --reference="$file2" "$file1"
    echo "Metadata updated: $file1" >> "$LOGFILE"
    return 0
  else
    # Si les métadonnées et le contenu des deux fichiers sont différents, il y a un conflit, retourne 1
    return 1
  fi
}

# Définir des fonctions pour synchroniser les fichiers dans un répertoire, descendant récursivement
sync_dir() {
  dir1=$1
  dir2=$2
  # Parcourez tous les fichiers du premier répertoire.
  for file1 in "$dir1"/*; do
    # Obtenir le nom de fichier et le chemin correspondants.
    filename=$(basename "$file1")
    file2="$dir2/$filename"
    if [ -d "$file1" ]; then
      if [ ! -d "$file2" ]; then
        # Il y a un conflit si le premier fichier est un répertoire, mais le second ne l’est pas.
        echo "Conflict: $file1 is a directory, but $file2 is not." >&2
        return 1
      else
        # Descend récursivement si les deux fichiers sont des répertoires.
        sync_dir "$file1" "$file2"
      fi
    elif [ -f "$file1" ]; then
      if [ ! -f "$file2" ]; then
        # Il y a un conflit si le premier fichier est normal mais le second ne l’est pas.
        echo "Conflict: $file1 is a regular file, but $file2 is not." >&2
        return 1
      else
        # Si les deux fichiers sont normaux, comparez leur contenu et leurs métadonnées.
        if cmp -s "$file1" "$file2"; then
          # La synchronisation est réussie si le contenu et les métadonnées des deux fichiers sont identiques.
          echo "Sync successful: $file1 and $file2 are identical."
        elif [ "$file1" -nt "$file2" ]; then
          # Copier du premier au deuxième fichier si le premier fichier est plus récent que le second.
          echo "Syncing: $file1 -> $file2"
          cp "$file1" "$file2"
          # Enregistrement des opérations de synchronisation dans un fichier journal.
          echo "$(date +%Y-%m-%d\ %H:%M:%S) $file1 -> $file2" >> "$log_file"
        elif [ "$file2" -nt "$file1" ]; then
          # Copier du second au premier si le second fichier est plus récent que le premier.
          echo "Syncing: $file2 -> $file1"
          cp "$file2" "$file1"
          # Enregistrement des opérations de synchronisation dans un fichier journal.
          echo "$(date +%Y-%m-%d\ %H:%M:%S) $file2 -> $file1" >> "$log_file"
        else
          # Conflit si les métadonnées des deux fichiers sont différentes.
          echo "Conflict: $file1 and $file2 have different metadata." >&2
          return 1
        fi
      fi
    fi
  done
}
 