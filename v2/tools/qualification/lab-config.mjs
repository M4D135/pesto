// Configuration locale du labo, non versionnée : lab.local.json à côté de ce module
// ({"domain":"labo.local","netbios":"LABO","guestPasswordFile":"C:\\…\\xxx-admin.txt"}), sinon les variables
// PESTO_LABO_DOMAINE, PESTO_LABO_NETBIOS et PESTO_LABO_MDP_FICHIER. Le fichier de mot de passe n'est jamais lu ici :
// seul son chemin circule (--passwordfile). L'import ne lève rien ; une valeur absente lève au moment où elle sert.
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const FILE = path.join(path.dirname(fileURLToPath(import.meta.url)), 'lab.local.json');
let cache;

function config() {
  if (cache === undefined) cache = existsSync(FILE) ? JSON.parse(readFileSync(FILE, 'utf8')) : {};
  return cache;
}

function required(key, variable) {
  const value = config()[key] || process.env[variable];
  if (!value) throw new Error(`Configuration du labo absente : « ${key} » dans ${FILE} ou ${variable}.`);
  return value;
}

export const laboDomaine = () => required('domain', 'PESTO_LABO_DOMAINE');
export const laboNetbios = () => config().netbios || process.env.PESTO_LABO_NETBIOS || laboDomaine().split('.')[0].toUpperCase();
export const laboMdpFichier = () => required('guestPasswordFile', 'PESTO_LABO_MDP_FICHIER');
