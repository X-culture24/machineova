import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { api, setUnauthorizedHandler, token, type Me } from "./api";

interface AuthState {
  me: Me | null;
  loading: boolean;
  signIn: (login: string, password: string) => Promise<Me>;
  signOut: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(() => token.get() !== null);

  const signOut = useCallback(() => {
    token.set(null);
    setMe(null);
  }, []);

  useEffect(() => {
    setUnauthorizedHandler(signOut);
    if (!token.get()) return;
    api
      .me()
      .then(setMe)
      .catch(signOut)
      .finally(() => setLoading(false));
  }, [signOut]);

  const signIn = useCallback(async (login: string, password: string) => {
    const res = await api.login(login, password);
    token.set(res.token);
    setMe(res.user);
    return res.user;
  }, []);

  return <AuthContext.Provider value={{ me, loading, signIn, signOut }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth outside AuthProvider");
  return ctx;
}

export const isManager = (me: Me | null) => me?.role === "owner" || me?.role === "admin";
