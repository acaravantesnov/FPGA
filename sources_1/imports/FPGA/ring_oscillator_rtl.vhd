--==============================================================================
-- Title       : Ring Oscillator
-- File        : ring_oscillator.vhd
-- Description : Ring Oscillator with configurable number of inverters.
-- Generics    : g_n_inverters ->   Number of inverters within the RO. Number
--                                  must be odd.
-- Author      : Alberto Caravantes Arranz
-- Date        : 06/04/2025
-- Version     : 1.0
--==============================================================================

-- Revision History:
-- Version 1.0 - Initial version

library ieee;
use ieee.std_logic_1164.all;

entity ring_oscillator is
    generic(
        g_n_inverters: natural := 5
    );
    port(
        enable:     in std_logic;
        clk_out:    out std_logic
    );
end entity ring_oscillator;

architecture rtl of ring_oscillator is

    signal aux_i: std_logic_vector(g_n_inverters downto 0);
    
    -- Atributos para evitar optimizaciones del sintetizador
    attribute syn_keep          : boolean;
    attribute syn_keep of aux_i : signal is true;
    attribute keep : string;
    attribute keep of aux_i : signal is "true";

begin

    aux_i(0) <= enable and aux_i(g_n_inverters);

    GEN_RO: for i in 1 to g_n_inverters generate
            aux_i(i) <= not aux_i(i - 1);
    end generate GEN_RO;
    
    clk_out <= aux_i(0);

end architecture rtl;
