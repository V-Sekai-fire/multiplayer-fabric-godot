use keyring::{Entry, Error as KeyError};
use rustler::{Encoder, Env, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        not_found,
    }
}

/// Get a password from the OS keychain.
/// Returns {:ok, password} | {:error, :not_found} | {:error, message}.
#[rustler::nif(schedule = "DirtyIo")]
fn get_password<'a>(env: Env<'a>, service: String, user: String) -> Term<'a> {
    let entry = match Entry::new(&service, &user) {
        Ok(e) => e,
        Err(e) => return (atoms::error(), e.to_string()).encode(env),
    };
    match entry.get_password() {
        Ok(pw) => (atoms::ok(), pw).encode(env),
        Err(KeyError::NoEntry) => (atoms::error(), atoms::not_found()).encode(env),
        Err(e) => (atoms::error(), e.to_string()).encode(env),
    }
}

/// Set (insert or overwrite) a password in the OS keychain.
/// Returns :ok | {:error, message}.
#[rustler::nif(schedule = "DirtyIo")]
fn set_password<'a>(env: Env<'a>, service: String, user: String, password: String) -> Term<'a> {
    let entry = match Entry::new(&service, &user) {
        Ok(e) => e,
        Err(e) => return (atoms::error(), e.to_string()).encode(env),
    };
    match entry.set_password(&password) {
        Ok(()) => atoms::ok().encode(env),
        Err(e) => (atoms::error(), e.to_string()).encode(env),
    }
}

/// Delete a password from the OS keychain.
/// Returns :ok | {:error, :not_found} | {:error, message}.
#[rustler::nif(schedule = "DirtyIo")]
fn delete_credential<'a>(env: Env<'a>, service: String, user: String) -> Term<'a> {
    let entry = match Entry::new(&service, &user) {
        Ok(e) => e,
        Err(e) => return (atoms::error(), e.to_string()).encode(env),
    };
    match entry.delete_credential() {
        Ok(()) => atoms::ok().encode(env),
        Err(KeyError::NoEntry) => (atoms::error(), atoms::not_found()).encode(env),
        Err(e) => (atoms::error(), e.to_string()).encode(env),
    }
}

rustler::init!("Elixir.ZoneConsole.Keychain.Nif");
