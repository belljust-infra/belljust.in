---
title: "Prisoner's Dilemma and Commitment Schemes"
date: 2017-10-16T13:07:05-04:00
---

## Prisoner's Dilemma

[The Prisoner's Dilemma](https://en.wikipedia.org/wiki/Prisoner%27s_dilemma) is a popularly analyzed example in game theory.
Two prisoners, \\(A\\) and \\(B\\), have no means of communicating with each other.
Prisoners are allowed to betray or stay loyal to each other; the result of \\(A\\)'s choice depends on \\(B\\)'s and vice versa.
These are the potential scenarios:

- \\(A\\) and \\(B\\) both betray each other \\(\implies\\) each serves 2 years in prison
- \\(A\\) betrays \\(B\\), but \\(B\\) remains loyal \\(\implies\\) \\(A\\) gets off free but \\(B\\) serves 3 years (or vice versa)
- \\(A\\) and \\(B\\) both remain loyal \\(\implies\\) both serve 1 year in prison

(A, B)        | A betrays | A is loyal |
--------------|-----------|------------|
**B betrays** | (-2, -2)  | (-3, 0)    |
**B is loyal**| (0, -3)   | (-1, -1)   |
*payoff table of possible scenarios*

Many interesting things can already be said about *Nash Equilibriums*, *dominant strategies*, and more but the game becomes even more interesting when we consider an iterated variant.
In other words, instead of just one game, \\(A\\) and \\(B\\) play \\(N\\) games.
This allows them to base future decisions on their opponent's behaviour in the past.

### Tit-for-tat

Tit-for-tat is a simple strategy that does very well at iterated prisoner's dilemma (IPD) games.
Essentially, a player using a tit-for-tat startegy makes an *optimistic* move at the beginning, i.e. remains loyal, and subsequently responds the same as the opposing player.

Obviously, if the opponent is always mean, the mean guy will have the advantage.
However, when played against a diverse set of strategies, Tit-for-Tat will generally do well in comparison.
In fact, [Axelrod's Tournament](https://cs.stanford.edu/people/eroberts/courses/soco/projects/1998-99/game-theory/axelrod.html) is a famous example of tit-for-tat as a winning strategy.

A tit-for-tat variant is also used in the popular BitTorrent protocol where clients *optimistically unchoke* a peer, i.e. start sending them data.
If that peer reciprocates, then continue sending data.
For those familiar with downloading large files via a Torrent, you'll know that this is a succesful protocol.

## IPD as a Service

Wouldn't it be cool if there was a constant service that would allow people to play IPD games?
Better yet, bots could be used to plays these games - potentially learning better strategies that could improve our P2P protocols!

I started to build such a service some time ago.
First, I started with the idea that users could upload their bots which I could then run against each other on my server.
Few problems with this:

- it's not very safe. I didn't really trust myself to safely execute user code on my own server. Without properly managed resource limits, bots could crash my server. Or worse, a poorly sandboxed environment could gain access to my system!
- expensive. If I want people to do interesting things, it will probably require a lot of resources. If I'm running the bots, I'm footing the bill for those resources

Next, I considered having endpoints where bots could POST their responses and GET their opponent's responses.
This seemed like an inelegant solution because the server would either have to:

- setup and tear down hundreds/thousands of connections for one iterated game, or
- maintain a connection for the entire game (which could take very long).

Not to mention I'd, again, have to pay for all that traffic.

So, what am I left with?
A peer-to-peer (P2P) network where my server acts as a directory of availble peers.
Bots could then connect to my server exactly once, ask for a fellow bot, then start a game linked directly to that bot.

## Commitment Schemes

One issue with the P2P setup is trust.
\\(A\\) and \\(B\\) have to exchange messages but it would be cheating if either of them could know their opponent's answer before making a response.

For example, \\(A\\) sends a betray message to \\(B\\).
If \\(B\\) could "peek", the only logical thing to do is betray in return.
This gives her an advantage over \\(A\\).

Without an intermediary that they trust (like a server), it's not obvious how \\(A\\) and \\(B\\) can know the other isn't cheating.
What we need is some way to communicate that we've committed to a response without revealing it.
This is exactly what a [commitment scheme](https://en.wikipedia.org/wiki/Commitment_scheme) provides.

I learned about these thanks to an invaluable [answer](https://crypto.stackexchange.com/a/51961/51775) to my question on the cryptography stack exchange.
It was also cool to learn that Claude Crepeau, a previous algorithm professor of mine, was one of the researches responsble for [formalizing the idea in 1988](http://crypto.cs.mcgill.ca/~crepeau/PDF/BCC88-jcss.pdf).

The basic idea is to send some commitment of the message, \\(c(a)\\), that can later be verified.
Once, the commitment has been recieved, B can send it's message to A.
Finally A can send the message she's commited to.

$$
\begin{align}
    A\to B:\quad &c(a)\\\\\\
    B\to A:\quad &b\\\\\\
    A\to B:\quad &a
\end{align}
$$
*commitment scheme*

### commitment
But what is this commitment, \\(c(a)\\)?
It must have two properties to be sufficient:

- it must not be feasible for \\(A\\) to change her answer after making a commitment, and
- the commitment must not leak information

Luckily a cryptographic hash, e.g. SHA256, can provide exactly this!

To stop users from precomputing all the message hashes, which is trivial because there's only two valid responses, we'll need to salt the message with some random data.
The commitment is then some random data, \\(k\\) concated with the message which is SHA256 hashed,

$$
    c(a) = SHA256(k \Vert a)
$$
*commitment*

The message that \\(A\\) finally sends now includes the random data as well.
\\(B\\) can check the last bit for \\(A\\)'s response and verify it by hashing it and comparing it to the commitment it recieved previously

$$
v(k \Vert a) = 
    \begin{cases}
        True,   &SHA256(k \Vert a) = c(a) \\\\\\
        False,  &SHA256(k \Vert a) \neq c(a) \\\\\\
    \end{cases}
$$
*verifying the commitment*

Putting all this together in psuedo-python looks like this:

{{< highlight python >}}
def host_play(a):
    # Generate your salt
    k = randbit(32)

    # Send a hash of the salt concated to your msg
    send(sha256(k+a))

    # Wait to receive opponent's message
    b = recv()

    # Send the non-hashed concatenation of the salt and msg
    send(k+a)
    return b

def guest_play(b):
    # Wait to recieve the commitment
    c = recv()

    # Send your msg
    send(b)

    # Recieve your opponent's salt and msg
    m = recv() 

    # Verify the hash matches the commitment
    if sha256(m) != c:
        raise CheatedException("Your opponent cheated!")

    # The last bit contains your opponent's response
    return m[-1]

{{< \highlight >}}
